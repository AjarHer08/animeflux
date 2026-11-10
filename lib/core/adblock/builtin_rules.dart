/// Aturan filter bawaan (offline, tanpa perlu download).
///
/// Format mengikuti sintaks Adblock Plus / uBlock / AdGuard (subset):
///   ||domain^          blokir domain & subdomain
///   ##selector         sembunyikan elemen (semua situs)
///   situs.com##sel     sembunyikan elemen hanya di situs tertentu
library;

/// Host yang TIDAK pernah diblokir (sumber konten aplikasi sendiri).
const List<String> kAdblockNeverBlock = [
  'komiku.org',
  'komikstation.org',
  'kiryuu.to',
  'kiryuu.id',
  'kiryuu.io',
  'otakudesu.blog',
  'hidoristream.online',
  'lendrive.web.id',
];

const String kBuiltinFilterList = r'''
! AnimeFlux base list — iklan, popunder, dan banner judi online yang umum
! muncul di situs anime/komik berbahasa Indonesia.
! --- Jaringan iklan umum ---
||doubleclick.net^
||googlesyndication.com^
||googleadservices.com^
||adservice.google.com^
||pagead2.googlesyndication.com^
||amazon-adsystem.com^
||adnxs.com^
||rubiconproject.com^
||pubmatic.com^
||openx.net^
||criteo.com^
||criteo.net^
||casalemedia.com^
||adform.net^
||smartadserver.com^
||moatads.com^
||taboola.com^
||outbrain.com^
||revcontent.com^
||mgid.com^
||adskeeper.com^
||adcash.com^
||bidvertiser.com^
||yllix.com^
||ad-maven.com^
||admaven.com^
! --- Popunder / push / redirect ---
||popads.net^
||popcash.net^
||propellerads.com^
||propu.sh^
||onclickads.net^
||clickadu.com^
||hilltopads.net^
||richads.com^
||notix.io^
||pushwhy.com^
||exoclick.com^
||exosrv.com^
||realsrv.com^
||magsrv.com^
||juicyads.com^
||trafficjunky.com^
||trafficstars.com^
||tsyndicate.com^
||adtng.com^
||ero-advertising.com^
||popunder.net^
||a-ads.com^
||adsterra.com^
||highperformanceformat.com^
||effectivegatecpm.com^
||profitablecpmrate.com^
||profitablegatecpm.com^
||dolohen.com^
||acscdn.com^
||cdn4ads.com^
! --- Banner judi online yang terlihat di situs sumber ---
||klikcdn.com^
||akseskdslot.net^
||aksesin.top^
||klik.top^
||88cdn.cloud^
||kegz.site^
||menujupenta.site^
||goid.space^
||cek.to^
! --- Elemen iklan (semua situs) ---
##ins.adsbygoogle
##.adsbygoogle
##[id^="google_ads_"]
##[id^="div-gpt-ad"]
##iframe[src*="doubleclick.net"]
##iframe[src*="googlesyndication.com"]
##a[href*="klikcdn.com"]
##a[href*="akseskdslot.net"]
##a[href*="aksesin.top"]
##img[src*="klikcdn.com"]
##img[src*="88cdn.cloud"]
##a[href*="menujupenta.site"]
##a[href*="kegz.site"]
##a[href*="goid.space"]
##.ads
##.ads-banner
##.banner-ads
##.ad-banner
##.adsbox
##.iklan
##.pop-ads
##.popup-ads
##.sticky-ads
##.floating-ads
###ads
###iklan
##[class*="ads-container"]
##[class*="adv-container"]
##[id*="banner-ad"]
##[id*="ads-banner"]
''';

/// Daftar langganan opsional (diunduh saat pengguna mengaktifkan).
/// URL dapat berubah — kalau gagal diunduh, UI menampilkan pesan error.
class BuiltinSubscription {
  final String id;
  final String name;
  final String description;
  final String url;
  const BuiltinSubscription(this.id, this.name, this.description, this.url);
}

const List<BuiltinSubscription> kBuiltinSubscriptions = [
  BuiltinSubscription(
    'adguard-base',
    'AdGuard Base',
    'Filter iklan utama AdGuard (format uBlock).',
    'https://filters.adtidy.org/extension/ublock/filters/2.txt',
  ),
  BuiltinSubscription(
    'adguard-mobile',
    'AdGuard Mobile Ads',
    'Filter iklan khusus perangkat mobile.',
    'https://filters.adtidy.org/extension/ublock/filters/11.txt',
  ),
  BuiltinSubscription(
    'ublock-filters',
    'uBlock filters',
    'Filter resmi uBlock Origin (iklan, popup, anti-adblock).',
    'https://ublockorigin.github.io/uAssets/filters/filters.min.txt',
  ),
  BuiltinSubscription(
    'easylist',
    'EasyList',
    'Daftar iklan terbesar dan paling umum dipakai.',
    'https://easylist.to/easylist/easylist.txt',
  ),
  BuiltinSubscription(
    'abpindo',
    'ABPindo (Indonesia)',
    'Filter tambahan untuk situs berbahasa Indonesia.',
    'https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt',
  ),
  BuiltinSubscription(
    'peter-lowe',
    'Peter Lowe ad servers',
    'Daftar host server iklan & tracker (format hosts).',
    'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext',
  ),
];
