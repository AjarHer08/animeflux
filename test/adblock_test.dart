import 'package:animeflux/core/adblock/adblock_engine.dart';
import 'package:animeflux/core/adblock/filter_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FilterParser', () {
    final parsed = FilterParser.parse('''
! komentar
||ads.example.com^
||tracker.net^\$third-party
@@||ok.example.com^
0.0.0.0 evil.test
##.banner
site.com##.promo
site.com#?#div:has-text(x)
||bad.com^\$redirect=noop.js
''');

    test('blokir host & format hosts', () {
      expect(parsed.blockHosts, containsAll(['ads.example.com', 'tracker.net', 'evil.test']));
    });
    test('pengecualian dan opsi tak didukung', () {
      expect(parsed.allowHosts, contains('ok.example.com'));
      expect(parsed.blockHosts, isNot(contains('bad.com')));
    });
    test('cosmetic umum dan per-domain', () {
      expect(parsed.genericCss, contains('.banner'));
      expect(parsed.domainCss['site.com'], contains('.promo'));
    });
  });

  group('AdblockRuleSet', () {
    final rules = AdblockRuleSet({'ads.example.com'}, {'ok.ads.example.com'}, []);
    test('subdomain ikut diblokir', () {
      expect(rules.isBlocked('https://x.ads.example.com/a.js'), isTrue);
    });
    test('allow mengalahkan block', () {
      expect(rules.isBlocked('https://ok.ads.example.com/a.js'), isFalse);
    });
    test('host lain aman', () {
      expect(rules.isBlocked('https://example.com/'), isFalse);
    });
  });
}
