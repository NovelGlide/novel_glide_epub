import 'package:novel_glide_epub/src/readers/package_reader.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_spine.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

void main() {
  group('EpubSpine page-progression-direction', () {
    test('rtl direction sets ltr to false', () {
      final XmlElement spineNode = XmlDocument.parse(
        '<spine page-progression-direction="rtl">'
        '  <itemref idref="chapter1" />'
        '</spine>',
      ).rootElement;

      final EpubSpine spine = const PackageReader().readSpine(spineNode);

      expect(spine.ltr, isFalse);
    });

    test('ltr direction sets ltr to true', () {
      final XmlElement spineNode = XmlDocument.parse(
        '<spine page-progression-direction="ltr">'
        '  <itemref idref="chapter1" />'
        '</spine>',
      ).rootElement;

      final EpubSpine spine = const PackageReader().readSpine(spineNode);

      expect(spine.ltr, isTrue);
    });

    test('no page-progression-direction defaults to ltr', () {
      final XmlElement spineNode = XmlDocument.parse(
        '<spine>'
        '  <itemref idref="chapter1" />'
        '</spine>',
      ).rootElement;

      final EpubSpine spine = const PackageReader().readSpine(spineNode);

      expect(spine.ltr, isTrue);
    });

    test('RTL direction (uppercase) sets ltr to false', () {
      final XmlElement spineNode = XmlDocument.parse(
        '<spine page-progression-direction="RTL">'
        '  <itemref idref="chapter1" />'
        '</spine>',
      ).rootElement;

      final EpubSpine spine = const PackageReader().readSpine(spineNode);

      expect(spine.ltr, isFalse);
    });
  });
}
