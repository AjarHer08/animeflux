/// Mesin pemblokir iklan bawaan aplikasi (gaya AdGuard / uBlock Origin).
///
/// Catatan penting: ini BUKAN ekstensi browser (WebExtensions) — ekstensi
/// Chrome/Firefox tidak bisa dimuat di Android WebView. Sebagai gantinya,
/// aplikasi punya engine sendiri yang membaca filter list berformat sama
/// (EasyList / AdGuard / uBlock) dan menerapkannya di WebView:
///   1. blokir request jaringan (native content blocker),
///   2. sembunyikan elemen iklan (cosmetic CSS),
///   3. blokir popup, redirect otomatis, dan overlay link transparan.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/http_client.dart';
import '../utils/logger.dart';
import 'builtin_rules.dart';
import 'filter_parser.dart';

/// Hasil kompilasi aturan yang siap dipakai untuk pengecekan URL di Dart.
class AdblockRuleSet {
  final Set<String> block;
  final Set<String> allow;
  final List<RegExp> paths;

  AdblockRuleSet(this.block, this.allow, this.paths);
  factory AdblockRuleSet.empty() => AdblockRuleSet(<String>{}, <String>{}, <RegExp>[]);

  static bool _matchesHost(Set<String> set, String host) {
    var h = host;
    while (true) {
      if (set.contains(h)) return true;
      final dot = h.indexOf('.');
      if (dot == -1) return false;
      h = h.substring(dot + 1);
      if (!h.contains('.')) return false; // jangan cocokkan TLD saja
    }
  }

  bool isBlocked(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    if (_matchesHost(allow, host)) return false;
    if (_matchesHost(block, host)) return true;
    for (final re in paths) {
      if (re.hasMatch(url)) return true;
    }
    return false;
  }
}

class FilterListInfo {
  final String id;
  final String name;
  final String description;
  final String? url;
  final bool builtin; // daftar bawaan (tidak bisa dihapus)
  final bool custom; // ditambahkan pengguna
  final bool enabled;
  final int ruleCount;
  final DateTime? updatedAt;
  final bool downloading;
  final String? error;

  const FilterListInfo({
    required this.id,
    required this.name,
    this.description = '',
    this.url,
    this.builtin = false,
    this.custom = false,
    this.enabled = false,
    this.ruleCount = 0,
    this.updatedAt,
    this.downloading = false,
    this.error,
  });

  FilterListInfo copyWith({
    bool? enabled,
    int? ruleCount,
    DateTime? updatedAt,
    bool? downloading,
    String? error,
    bool clearError = false,
  }) {
    return FilterListInfo(
      id: id,
      name: name,
      description: description,
      url: url,
      builtin: builtin,
      custom: custom,
      enabled: enabled ?? this.enabled,
      ruleCount: ruleCount ?? this.ruleCount,
      updatedAt: updatedAt ?? this.updatedAt,
      downloading: downloading ?? this.downloading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'url': url,
        'builtin': builtin,
        'custom': custom,
        'enabled': enabled,
        'ruleCount': ruleCount,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory FilterListInfo.fromJson(Map<String, dynamic> j) => FilterListInfo(
        id: j['id'] as String,
        name: j['name'] as String? ?? (j['id'] as String),
        description: j['description'] as String? ?? '',
        url: j['url'] as String?,
        builtin: j['builtin'] as bool? ?? false,
        custom: j['custom'] as bool? ?? false,
        enabled: j['enabled'] as bool? ?? false,
        ruleCount: j['ruleCount'] as int? ?? 0,
        updatedAt: j['updatedAt'] != null ? DateTime.tryParse(j['updatedAt'] as String) : null,
      );
}

/// Dipakai compute(): parsing tiap teks secara terpisah (hitung rule per list).
List<ParsedFilters> _parseEach(List<String> texts) =>
    texts.map(FilterParser.parse).toList();

class AdblockEngine extends ChangeNotifier {
  AdblockEngine._();
  static final AdblockEngine instance = AdblockEngine._();

  static const _cfgKey = 'adblock_v1_cfg';
  static const _builtinId = 'builtin';
  static const int _maxNativeHosts = 6000;
  static const int _hostChunk = 300;
  static const int _pathChunk = 100;

  SharedPreferences? _prefs;

  bool enabled = true;
  bool blockPopups = true;
  bool cosmetic = true;
  String customRules = '';
  List<FilterListInfo> lists = <FilterListInfo>[];

  /// Popup / redirect / navigasi iklan yang dibatalkan sesi ini.
  int blockedCount = 0;
  bool busy = false;
  String? message;

  AdblockRuleSet _rules = AdblockRuleSet.empty();
  ParsedFilters _parsed = ParsedFilters();
  List<ContentBlocker> _contentBlockers = const [];

  int get totalRules => _parsed.ruleCount;
  List<ContentBlocker> get contentBlockers => enabled ? _contentBlockers : const [];

  // ---------------------------------------------------------------- init

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    _loadConfig();
    await rebuild();
  }

  List<FilterListInfo> _defaultLists() => [
        const FilterListInfo(
          id: _builtinId,
          name: 'AnimeFlux Base (bawaan)',
          description: 'Jaringan iklan, popunder, dan banner judi online. Bekerja offline.',
          builtin: true,
          enabled: true,
        ),
        for (final s in kBuiltinSubscriptions)
          FilterListInfo(id: s.id, name: s.name, description: s.description, url: s.url),
      ];

  void _loadConfig() {
    final defaults = _defaultLists();
    final raw = _prefs?.getString(_cfgKey);
    if (raw == null) {
      lists = defaults;
      return;
    }
    try {
      final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      enabled = j['enabled'] as bool? ?? true;
      blockPopups = j['blockPopups'] as bool? ?? true;
      cosmetic = j['cosmetic'] as bool? ?? true;
      customRules = j['customRules'] as String? ?? '';
      final saved = <String, FilterListInfo>{
        for (final e in (j['lists'] as List? ?? const []))
          (e as Map)['id'] as String: FilterListInfo.fromJson(Map<String, dynamic>.from(e)),
      };
      final merged = <FilterListInfo>[];
      for (final d in defaults) {
        final s = saved.remove(d.id);
        merged.add(s == null
            ? d
            : d.copyWith(enabled: s.enabled, ruleCount: s.ruleCount, updatedAt: s.updatedAt));
      }
      // Sisanya = daftar custom milik pengguna.
      merged.addAll(saved.values.where((e) => e.custom));
      lists = merged;
    } catch (e) {
      logger.w('Adblock: config rusak, pakai default ($e)');
      lists = defaults;
    }
  }

  Future<void> _saveConfig() async {
    await _prefs?.setString(
      _cfgKey,
      jsonEncode({
        'enabled': enabled,
        'blockPopups': blockPopups,
        'cosmetic': cosmetic,
        'customRules': customRules,
        'lists': lists.map((e) => e.toJson()).toList(),
      }),
    );
  }

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/adblock');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _fileFor(String id) async => File('${(await _dir()).path}/$id.txt');

  // ------------------------------------------------------------ setters

  Future<void> setEnabled(bool v) async {
    enabled = v;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setBlockPopups(bool v) async {
    blockPopups = v;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setCosmetic(bool v) async {
    cosmetic = v;
    await _saveConfig();
    notifyListeners();
  }

  Future<void> setCustomRules(String text) async {
    customRules = text;
    await _saveConfig();
    await rebuild();
  }

  Future<void> setListEnabled(String id, bool value) async {
    final i = lists.indexWhere((e) => e.id == id);
    if (i < 0) return;
    lists[i] = lists[i].copyWith(enabled: value, clearError: true);
    notifyListeners();
    if (value && !lists[i].builtin) {
      final f = await _fileFor(id);
      if (!await f.exists()) {
        await updateList(id); // updateList sudah memanggil rebuild
        return;
      }
    }
    await _saveConfig();
    await rebuild();
  }

  Future<void> addCustomList(String name, String url) async {
    final id = 'custom-${DateTime.now().millisecondsSinceEpoch}';
    lists.add(FilterListInfo(
      id: id,
      name: name.isEmpty ? Uri.tryParse(url)?.host ?? 'Daftar kustom' : name,
      url: url,
      custom: true,
      enabled: true,
    ));
    notifyListeners();
    await updateList(id);
  }

  Future<void> removeList(String id) async {
    final i = lists.indexWhere((e) => e.id == id);
    if (i < 0 || !lists[i].custom) return;
    lists.removeAt(i);
    try {
      final f = await _fileFor(id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _saveConfig();
    await rebuild();
  }

  /// Unduh (ulang) filter list dari URL-nya lalu bangun ulang aturan.
  Future<void> updateList(String id) async {
    final i = lists.indexWhere((e) => e.id == id);
    if (i < 0 || lists[i].url == null) return;
    lists[i] = lists[i].copyWith(downloading: true, clearError: true);
    notifyListeners();
    try {
      final res = await HttpClient.instance.raw.get<String>(
        lists[i].url!,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
      final body = res.data ?? '';
      if ((res.statusCode ?? 0) != 200 || body.length < 100) {
        throw Exception('HTTP ${res.statusCode}, isi terlalu kecil');
      }
      if (body.length > 25 * 1024 * 1024) throw Exception('File terlalu besar');
      await (await _fileFor(id)).writeAsString(body);
      final j = lists.indexWhere((e) => e.id == id);
      if (j >= 0) {
        lists[j] = lists[j].copyWith(downloading: false, updatedAt: DateTime.now(), clearError: true);
      }
      await _saveConfig();
      await rebuild();
    } catch (e) {
      final j = lists.indexWhere((x) => x.id == id);
      if (j >= 0) lists[j] = lists[j].copyWith(downloading: false, error: '$e');
      logger.w('Adblock: gagal unduh $id: $e');
      notifyListeners();
    }
  }

  Future<void> updateAllEnabled() async {
    for (final l in List<FilterListInfo>.of(lists)) {
      if (l.enabled && l.url != null) await updateList(l.id);
    }
  }

  // ------------------------------------------------------------ rebuild

  Future<void> rebuild() async {
    busy = true;
    notifyListeners();
    try {
      final ids = <String>[];
      final texts = <String>[];
      for (final l in lists) {
        if (!l.enabled) continue;
        if (l.builtin) {
          ids.add(l.id);
          texts.add(kBuiltinFilterList);
        } else {
          final f = await _fileFor(l.id);
          if (await f.exists()) {
            ids.add(l.id);
            texts.add(await f.readAsString());
          }
        }
      }
      final customText = customRules.trim();
      if (customText.isNotEmpty) texts.add(customText);

      final parsedEach = await compute(_parseEach, texts);

      final all = ParsedFilters();
      for (var i = 0; i < parsedEach.length; i++) {
        all.merge(parsedEach[i]);
        if (i < ids.length) {
          final idx = lists.indexWhere((e) => e.id == ids[i]);
          if (idx >= 0) lists[idx] = lists[idx].copyWith(ruleCount: parsedEach[i].ruleCount);
        }
      }
      all.allowHosts.addAll(kAdblockNeverBlock);
      _parsed = all;

      final paths = <RegExp>[];
      for (final p in all.pathPatterns) {
        try {
          paths.add(RegExp(p, caseSensitive: false));
        } catch (_) {}
      }
      _rules = AdblockRuleSet(all.blockHosts, all.allowHosts, paths);
      _contentBlockers = _buildContentBlockers(all);
      await _saveConfig();
      message = null;
    } catch (e, st) {
      logger.e('Adblock rebuild gagal: $e\n$st');
      message = 'Gagal memproses filter: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  List<ContentBlocker> _buildContentBlockers(ParsedFilters f) {
    final blockers = <ContentBlocker>[];

    final hosts = f.blockHosts
        .where((h) => !f.allowHosts.contains(h))
        .toList()
      ..sort();
    final capped = hosts.length > _maxNativeHosts ? hosts.sublist(0, _maxNativeHosts) : hosts;
    for (var i = 0; i < capped.length; i += _hostChunk) {
      final chunk = capped.sublist(i, i + _hostChunk > capped.length ? capped.length : i + _hostChunk);
      final alt = chunk.map(RegExp.escape).join('|');
      blockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: r'^https?://([^/?#:]+\.)?(' + alt + r')([:/?#].*)?$',
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ));
    }

    final paths = f.pathPatterns;
    for (var i = 0; i < paths.length; i += _pathChunk) {
      final chunk = paths.sublist(i, i + _pathChunk > paths.length ? paths.length : i + _pathChunk);
      final alt = chunk.map((p) => '$p.*').join('|');
      blockers.add(ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: '(?:$alt)'),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ));
    }
    return blockers;
  }

  // ------------------------------------------------------------- runtime

  /// True kalau URL termasuk iklan (dipakai untuk navigasi & popup).
  bool isBlocked(String url) => enabled && _rules.isBlocked(url);

  /// Hitung request jaringan yang diblok tanpa memicu rebuild UI tiap request.
  int blockedRequests = 0;
  void noteBlockedQuiet() => blockedRequests++;

  void noteBlocked() {
    blockedCount++;
    notifyListeners();
  }

  /// UserScript (cosmetic + popup guard) untuk halaman dengan host tertentu.
  UserScript? buildUserScript(String pageHost) {
    if (!enabled || (!cosmetic && !blockPopups)) return null;

    final host = pageHost.toLowerCase();
    final specific = <String>[];
    var h = host;
    while (h.contains('.')) {
      final s = _parsed.domainCss[h];
      if (s != null) specific.addAll(s);
      h = h.substring(h.indexOf('.') + 1);
    }

    final generic = cosmetic ? _parsed.genericCss.toList() : const <String>[];
    final src = _scriptTemplate
        .replaceFirst('__GENERIC__', jsonEncode(generic))
        .replaceFirst('__SPECIFIC__', jsonEncode(cosmetic ? specific : const <String>[]))
        .replaceFirst('__COSMETIC__', cosmetic ? 'true' : 'false')
        .replaceFirst('__POPUP__', blockPopups ? 'true' : 'false');
    return UserScript(
      source: src,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    );
  }

  static const String _scriptTemplate = r'''
(function () {
  try {
    if (window.__afxAdblock) return;
    window.__afxAdblock = true;
    var GENERIC = __GENERIC__;
    var SPECIFIC = __SPECIFIC__;
    var COSMETIC = __COSMETIC__;
    var POPUP = __POPUP__;

    function validOnly(list) {
      var frag = document.createDocumentFragment();
      var ok = [];
      for (var i = 0; i < list.length; i++) {
        try { frag.querySelector(list[i]); ok.push(list[i]); } catch (e) {}
      }
      return ok;
    }

    function injectCss() {
      if (!COSMETIC) return;
      var all = validOnly(GENERIC.concat(SPECIFIC));
      if (!all.length) return;
      var css = '';
      for (var i = 0; i < all.length; i += 40) {
        css += all.slice(i, i + 40).join(',') +
          '{display:none!important;visibility:hidden!important}\n';
      }
      var st = document.createElement('style');
      st.setAttribute('data-afx', '1');
      st.textContent = css;
      (document.head || document.documentElement).appendChild(st);
    }
    injectCss();

    // Iklan video di dalam player embed (preroll VAST / overlay "Iklan ini akan
    // berakhir dalam N"): netralkan respons VAST, percepat video iklan sampai
    // habis, dan klik tombol "Skip" bila ada.
    if (COSMETIC) {
      // 1) Respons VAST/VMAP (XML iklan) diganti VAST kosong -> player tidak punya iklan.
      try {
        var vastRe = /<\s*(vmap:)?(VAST|VMAP)[\s>]/i;
        var EMPTY_VAST = '<?xml version="1.0" encoding="UTF-8"?><VAST version="3.0"></VAST>';
        var origFetch = window.fetch;
        if (origFetch) {
          window.fetch = function () {
            return origFetch.apply(this, arguments).then(function (res) {
              try {
                var ct = (res.headers && res.headers.get('content-type')) || '';
                if (/xml|text\/plain|text\/html/i.test(ct)) {
                  return res.clone().text().then(function (t) {
                    if (vastRe.test(t.slice(0, 800))) {
                      return new Response(EMPTY_VAST, { status: 200, headers: { 'content-type': 'text/xml' } });
                    }
                    return res;
                  }).catch(function () { return res; });
                }
              } catch (e) {}
              return res;
            });
          };
        }
        var xhrOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function () {
          var x = this;
          x.addEventListener('readystatechange', function () {
            if (x.readyState !== 4) return;
            try {
              var rt = x.responseType;
              var t = (rt === '' || rt === 'text') ? x.responseText : '';
              if (t && vastRe.test(t.slice(0, 800))) {
                Object.defineProperty(x, 'responseText', { configurable: true, value: EMPTY_VAST });
                Object.defineProperty(x, 'response', { configurable: true, value: EMPTY_VAST });
                Object.defineProperty(x, 'responseXML', {
                  configurable: true,
                  value: new DOMParser().parseFromString(EMPTY_VAST, 'text/xml'),
                });
              }
            } catch (e) {}
          });
          return xhrOpen.apply(this, arguments);
        };
      } catch (e) {}

      // 2) Deteksi keadaan "sedang iklan": percepat video pendek sampai selesai & skip.
      try {
        var skipRe = /^\s*(skip( ad| ads)?( \d+)?|lewati( iklan)?|tutup iklan|close ad)\s*$/i;
        var adTextRe = /iklan ini akan berakhir|iklan akan berakhir|ad will end|advertisement|ad ends in/i;
        var AD_SEL = '.jw-skip, .vjs-ad-skip-button, .videoAdUiSkipButton, .ytp-ad-skip-button, ' +
          '.vast-skip-button, [class*="adskip"], [id*="ad-skip"]';
        function tickAds() {
          try {
            var body = document.body;
            if (!body) return;
            var txt = body.innerText || '';
            if (adTextRe.test(txt)) {
              var vs = document.querySelectorAll('video');
              for (var k = 0; k < vs.length; k++) {
                var v = vs[k];
                var d = v.duration;
                // Iklan pendek (< 3 menit); episode asli jauh lebih panjang.
                if (isFinite(d) && d > 0 && d < 180) {
                  v.muted = true;
                  try { v.playbackRate = 16; } catch (e) {}
                  if (v.currentTime < d - 0.3) v.currentTime = d - 0.2;
                }
              }
            }
            var btns = document.querySelectorAll(AD_SEL + ', button, div[role="button"], a, span, div');
            for (var i = 0; i < btns.length; i++) {
              var b = btns[i];
              if (b.children.length > 2) continue;
              var t = (b.textContent || '').trim();
              if (t.length === 0 || t.length > 20) continue;
              if (skipRe.test(t) || b.matches(AD_SEL)) {
                var r = b.getBoundingClientRect();
                if (r.width > 0 && r.height > 0) b.click();
              }
            }
            var ads = document.querySelectorAll('.ima-ad-container, .ad-overlay, .plyr__ads');
            for (var j = 0; j < ads.length; j++) ads[j].style.setProperty('display', 'none', 'important');
          } catch (e) {}
        }
        setInterval(tickAds, 400);
      } catch (e) {}
    }

    if (POPUP) {
      try { window.open = function () { return null; }; } catch (e) {}

      // Hapus link transparan seukuran layar (trik klik-jacking untuk popunder).
      var sweeps = 0;
      var timer = null;
      function sweep() {
        timer = null;
        if (++sweeps > 25) return;
        try {
          var vw = window.innerWidth, vh = window.innerHeight;
          var links = document.querySelectorAll('a[href]');
          for (var i = 0; i < links.length; i++) {
            var el = links[i];
            var cs = getComputedStyle(el);
            if (cs.position !== 'fixed' && cs.position !== 'absolute') continue;
            var r = el.getBoundingClientRect();
            if (r.width < vw * 0.9 || r.height < vh * 0.9) continue;
            var z = parseInt(cs.zIndex, 10) || 0;
            if (z < 100) continue;
            if ((el.textContent || '').trim().length > 0) continue;
            if (el.querySelector('video,iframe,img,canvas')) continue;
            var target;
            try { target = new URL(el.href, location.href).host; } catch (e) { continue; }
            if (target === location.host) continue;
            el.remove();
          }
        } catch (e) {}
      }
      function schedule() { if (!timer) timer = setTimeout(sweep, 900); }
      try {
        new MutationObserver(schedule).observe(document.documentElement, { childList: true, subtree: true });
      } catch (e) {}
      document.addEventListener('DOMContentLoaded', schedule);
    }
  } catch (e) {}
})();
''';
}
