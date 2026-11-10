/// Parser filter (subset sintaks Adblock Plus / uBlock Origin / AdGuard).
///
/// Yang didukung:
///  * `||domain^` (+ opsi sederhana) → blokir host
///  * `||domain/path^` → pola path (regex)
///  * `@@||domain^` → pengecualian host
///  * format hosts (`0.0.0.0 domain`)
///  * `##selector` dan `situs.com##selector` → sembunyikan elemen (cosmetic)
///
/// Yang SENGAJA dilewati (butuh engine penuh): regex rules, scriptlet
/// (`+js`), selector prosedural (`:has-text`, `:xpath`, ...), `$redirect`,
/// `$removeparam`, `$csp`, `$domain=...`, dsb.
library;

import 'dart:collection';

class ParsedFilters {
  final Set<String> blockHosts = HashSet<String>();
  final Set<String> allowHosts = HashSet<String>();
  final List<String> pathPatterns = <String>[];
  final Set<String> genericCss = LinkedHashSet<String>();
  final Map<String, Set<String>> domainCss = <String, Set<String>>{};

  int get ruleCount =>
      blockHosts.length +
      pathPatterns.length +
      genericCss.length +
      domainCss.values.fold<int>(0, (a, b) => a + b.length);

  void merge(ParsedFilters other) {
    blockHosts.addAll(other.blockHosts);
    allowHosts.addAll(other.allowHosts);
    pathPatterns.addAll(other.pathPatterns);
    genericCss.addAll(other.genericCss);
    other.domainCss.forEach((k, v) {
      domainCss.putIfAbsent(k, () => LinkedHashSet<String>()).addAll(v);
    });
  }
}

class FilterParser {
  static const int maxPathPatterns = 1500;
  static const int maxGenericCss = 4000;

  static final RegExp _hostRe = RegExp(
      r'^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$');
  static final RegExp _hostsLine =
      RegExp(r'^(?:0\.0\.0\.0|127\.0\.0\.1|::1?)\s+(\S+)');
  static final RegExp _domainOnly =
      RegExp(r'^[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+$');

  static const List<String> _badOptions = [
    'domain=', 'badfilter', 'redirect', 'removeparam', 'csp', 'cookie',
    'header', 'replace', 'denyallow', 'rewrite', 'empty', 'mp4', 'generichide',
    'elemhide', 'specifichide', 'inline-script', 'inline-font', 'ping',
    'important-ignore',
  ];

  static const List<String> _badCosmetic = [
    '+js(', ':has-text', ':xpath', ':matches-css', ':upward', ':remove(',
    ':style(', ':contains(', ':nth-ancestor', ':watch-attr', ':min-text-length',
    ':others', ':-abp-', ':-js', ':matches-path', ':matches-media', ':not(:',
  ];

  static ParsedFilters parse(String text) {
    final out = ParsedFilters();
    for (final raw in text.split('\n')) {
      _parseLine(raw.trim(), out);
    }
    return out;
  }

  static void _parseLine(String line, ParsedFilters out) {
    if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) return;
    if (line.startsWith('#') && !line.startsWith('##')) return; // komentar hosts

    // Format hosts file.
    final hm = _hostsLine.firstMatch(line);
    if (hm != null) {
      final h = hm.group(1)!.toLowerCase();
      if (h != 'localhost' && _hostRe.hasMatch(h)) out.blockHosts.add(h);
      return;
    }

    // Cosmetic: ##selector atau a.com,b.com##selector
    final cosIdx = line.indexOf('##');
    if (cosIdx >= 0 && !line.startsWith('@@')) {
      _parseCosmetic(line.substring(0, cosIdx), line.substring(cosIdx + 2), out);
      return;
    }
    if (line.contains('#@#') ||
        line.contains('#?#') ||
        line.contains(r'#$#') ||
        line.contains('#%#')) {
      return;
    }

    // Domain polos (satu domain per baris, mis. daftar host sederhana).
    final lower = line.toLowerCase();
    if (_domainOnly.hasMatch(lower)) {
      out.blockHosts.add(lower);
      return;
    }

    // Network rule.
    var isAllow = false;
    var rule = line;
    if (rule.startsWith('@@')) {
      isAllow = true;
      rule = rule.substring(2);
    }
    if (rule.startsWith('/') && rule.endsWith('/')) return; // regex rule

    var options = '';
    final dollar = rule.lastIndexOf(r'$');
    if (dollar > 0) {
      options = rule.substring(dollar + 1).toLowerCase();
      rule = rule.substring(0, dollar);
    }
    if (options.isNotEmpty) {
      for (final bad in _badOptions) {
        if (options.contains(bad)) return;
      }
      // Negasi (~third-party, ~script, ...) mengubah makna → lewati.
      if (options.split(',').any((o) => o.startsWith('~'))) return;
    }

    if (!rule.startsWith('||')) return;
    final body = rule.substring(2);
    var end = body.length;
    for (final ch in const ['/', '^', '*', '?', ':', '|']) {
      final i = body.indexOf(ch);
      if (i >= 0 && i < end) end = i;
    }
    final host = body.substring(0, end).toLowerCase();
    final rest = body.substring(end);
    if (!_hostRe.hasMatch(host)) return;

    final hostOnly = rest.isEmpty || rest == '^' || rest == '^*' || rest == '|';
    if (hostOnly) {
      if (isAllow) {
        out.allowHosts.add(host);
      } else {
        out.blockHosts.add(host);
      }
      return;
    }

    // Pola dengan path → regex (hanya untuk aturan blokir).
    if (!isAllow &&
        rest.startsWith('/') &&
        out.pathPatterns.length < maxPathPatterns &&
        rest.length <= 120) {
      final buf = StringBuffer(r'^https?://([^/?#]+\.)?');
      buf.write(RegExp.escape(host));
      buf.write(_ruleToRegex(rest));
      out.pathPatterns.add(buf.toString());
    }
  }

  static String _ruleToRegex(String rest) {
    final buf = StringBuffer();
    for (var i = 0; i < rest.length; i++) {
      final c = rest[i];
      if (c == '*') {
        buf.write('.*');
      } else if (c == '^') {
        buf.write(r'([/?&:=]|$)');
      } else if (c == '|') {
        if (i == rest.length - 1) buf.write(r'$');
      } else {
        buf.write(RegExp.escape(c));
      }
    }
    return buf.toString();
  }

  static void _parseCosmetic(String domains, String selector, ParsedFilters out) {
    final sel = selector.trim();
    if (sel.isEmpty) return;
    for (final bad in _badCosmetic) {
      if (sel.contains(bad)) return;
    }
    if (sel.contains('{') || sel.contains('}')) return;

    if (domains.isEmpty) {
      if (out.genericCss.length < maxGenericCss) out.genericCss.add(sel);
      return;
    }
    final list = domains.split(',').map((d) => d.trim().toLowerCase()).toList();
    if (list.any((d) => d.startsWith('~') || d.isEmpty)) return;
    for (final d in list) {
      out.domainCss.putIfAbsent(d, () => LinkedHashSet<String>()).add(sel);
    }
  }
}

/// Dipakai `compute()` supaya parsing list besar tidak membekukan UI.
ParsedFilters parseFilterTexts(List<String> texts) {
  final all = ParsedFilters();
  for (final t in texts) {
    all.merge(FilterParser.parse(t));
  }
  return all;
}
