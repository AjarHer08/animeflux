/// Utility untuk HTML parsing dengan html package.
library;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';
import 'package:html_unescape/html_unescape.dart';

final _unescape = HtmlUnescape();

/// Decode HTML entities & trim whitespace
String cleanText(String? raw) {
  if (raw == null) return '';
  var t = _unescape.convert(raw);
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

/// Parse HTML string ke [dom.Document]
dom.Document parseHtml(String html) => HtmlParser(html).parse();

/// Ambil inner text dari element dengan selector
String? textFrom(dom.Document doc, String selector) {
  final el = doc.querySelector(selector);
  return cleanText(el?.text);
}

/// Ambil attribute dari element pertama yang cocok selector
String? attrFrom(dom.Document doc, String selector, String attr) {
  final el = doc.querySelector(selector);
  return el?.attributes[attr];
}

/// Resolve URL relatif menjadi absolute
String resolveUrl(String base, String? relative) {
  if (relative == null || relative.isEmpty) return base;
  if (relative.startsWith('http://') || relative.startsWith('https://')) {
    return relative;
  }
  if (relative.startsWith('//')) {
    return 'https:$relative';
  }
  if (relative.startsWith('/')) {
    final uri = Uri.parse(base);
    return '${uri.scheme}://${uri.host}$relative';
  }
  // relative tanpa leading slash
  final uri = Uri.parse(base);
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return '${uri.scheme}://${uri.host}$path$relative';
}
