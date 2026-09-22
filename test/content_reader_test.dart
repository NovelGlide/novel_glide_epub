// `ContentReader` — the manifest-to-content-map sorter.
//
// Two halves: the mime-type table (`getContentTypeByContentMimeType`) and the
// bucketing of manifest items into html / css / images / fonts / allFiles.
// The bucketing runs through a real `EpubReader.openBook`, because
// `parseContentMap` reads the schema off an opened book ref.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/readers/content_reader.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_content_ref.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

/// manifest entries covering every branch of the content-type switch, plus
/// the NCX the EPUB2 navigation reader needs.
const String _manifestItems = '<item id="ncx" href="toc.ncx" '
    'media-type="application/x-dtbncx+xml"/>'
    '<item id="ch1" href="chapter1.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '<item id="ch2" href="chapter2.html" media-type="text/html"/>'
    '<item id="dtb" href="book.dtbook" '
    'media-type="application/x-dtbook+xml"/>'
    '<item id="oeb" href="legacy.html" media-type="text/x-oeb1-document"/>'
    '<item id="xmlres" href="data.xml" media-type="application/xml"/>'
    '<item id="css" href="styles.css" media-type="text/css"/>'
    '<item id="oebcss" href="legacy.css" media-type="text/x-oeb1-css"/>'
    '<item id="gif" href="a.gif" media-type="image/gif"/>'
    '<item id="jpg" href="a.jpg" media-type="image/jpeg"/>'
    '<item id="png" href="a.png" media-type="image/png"/>'
    '<item id="svg" href="a.svg" media-type="image/svg+xml"/>'
    '<item id="bmp" href="a.bmp" media-type="image/bmp"/>'
    '<item id="ttf" href="a.ttf" media-type="font/truetype"/>'
    '<item id="otf" href="a.otf" media-type="font/opentype"/>'
    '<item id="msotf" href="ms.otf" '
    'media-type="application/vnd.ms-opentype"/>'
    '<item id="blob" href="a.bin" media-type="application/octet-stream"/>'
    '<item id="spaced" href="ch%20one.xhtml" '
    'media-type="application/xhtml+xml"/>';

const String _ncx = '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-CONTENT"/></head>'
    '<docTitle><text>NGE-SEED Content Map</text></docTitle>'
    '<navMap>'
    '<navPoint id="np-1" playOrder="1">'
    '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
    '<content src="chapter1.xhtml"/>'
    '</navPoint>'
    '</navMap>'
    '</ncx>';

Uint8List _buildBookWithEveryMediaType() => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:NGE-SEED-CONTENT</dc:identifier>'
            '<dc:title>NGE-SEED Content Map</dc:title>'
            '</metadata>'
            '<manifest>$_manifestItems</manifest>'
            '<spine toc="ncx"><itemref idref="ch1"/></spine>'
            '</package>',
        'OEBPS/toc.ncx': _ncx,
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
      },
    );

void main() {
  group('ContentReader.getContentTypeByContentMimeType', () {
    // TC-CNT-1 [Equivalence partitioning]: one case per mime type the table
    // knows, so a dropped row fails its own test rather than hiding inside a
    // bulk assertion.
    const Map<String, EpubContentType> table = <String, EpubContentType>{
      'application/xhtml+xml': EpubContentType.xhtml11,
      'text/html': EpubContentType.xhtml11,
      'application/x-dtbook+xml': EpubContentType.dtbook,
      'application/x-dtbncx+xml': EpubContentType.dtbookNcx,
      'text/x-oeb1-document': EpubContentType.oeb1Document,
      'application/xml': EpubContentType.xml,
      'text/css': EpubContentType.css,
      'text/x-oeb1-css': EpubContentType.oeb1Css,
      'image/gif': EpubContentType.imageGif,
      'image/jpeg': EpubContentType.imageJpeg,
      'image/png': EpubContentType.imagePng,
      'image/svg+xml': EpubContentType.imageSvg,
      'image/bmp': EpubContentType.imageBmp,
      'font/truetype': EpubContentType.fontTruetype,
      'font/opentype': EpubContentType.fontOpentype,
      'application/vnd.ms-opentype': EpubContentType.fontOpentype,
    };
    table.forEach((String mimeType, EpubContentType expected) {
      test(
        'TC-CNT-1 [Equivalence partitioning]: "$mimeType" maps to $expected',
        () {
          expect(
            const ContentReader().getContentTypeByContentMimeType(mimeType),
            expected,
          );
        },
      );
    });

    // TC-CNT-2 [Equivalence partitioning]: an unknown mime type falls through
    // to `EpubContentType.other` instead of throwing — a book with an
    // exotic resource still opens.
    test(
        'TC-CNT-2 [Equivalence partitioning]: an unknown mime type maps to '
        'other', () {
      expect(
        const ContentReader()
            .getContentTypeByContentMimeType('application/nge-seed'),
        EpubContentType.other,
      );
    });

    // TC-CNT-3 [Boundary value]: the lookup lower-cases first, so a manifest
    // that shouts its media type is still classified.
    test('TC-CNT-3 [Boundary]: the mime-type lookup is case-insensitive', () {
      expect(
        const ContentReader().getContentTypeByContentMimeType('IMAGE/PNG'),
        EpubContentType.imagePng,
      );
    });
  });

  group('ContentReader.parseContentMap', () {
    // TC-CNT-4 [Scenario/use-case]: text-shaped items reach html and css;
    // the text types with no bucket of their own (DTBOOK, NCX, OEB1
    // document, XML, OEB1 CSS) appear only in allFiles.
    test('TC-CNT-4 [Scenario]: text items are bucketed into html and css',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildBookWithEveryMediaType());
      final EpubContentRef content = bookRef.content!;

      expect(
        content.html!.keys,
        containsAll(<String>[
          'chapter1.xhtml',
          'chapter2.html',
          'ch%20one.xhtml',
        ]),
      );
      expect(content.css!.keys, containsAll(<String>['styles.css']));
      expect(content.css!.keys, isNot(contains('legacy.css')));
      expect(
        content.allFiles!.keys,
        containsAll(<String>[
          'toc.ncx',
          'book.dtbook',
          'legacy.html',
          'data.xml',
          'legacy.css',
        ]),
      );
    });

    // TC-CNT-5 [Scenario/use-case]: byte-shaped items split into images,
    // fonts, and the `EpubContentType.other` remainder that lands in
    // allFiles only.
    test('TC-CNT-5 [Scenario]: byte items are bucketed into images and fonts',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildBookWithEveryMediaType());
      final EpubContentRef content = bookRef.content!;

      expect(
        content.images!.keys,
        <String>['a.gif', 'a.jpg', 'a.png', 'a.svg', 'a.bmp'],
      );
      expect(content.fonts!.keys, <String>['a.ttf', 'a.otf', 'ms.otf']);
      expect(content.images!.keys, isNot(contains('a.bin')));
      expect(content.fonts!.keys, isNot(contains('a.bin')));
      expect(content.allFiles!.keys, contains('a.bin'));
    });

    // TC-CNT-6 [Boundary value]: a percent-encoded href keys the map RAW but
    // stores a decoded fileName — the two must not be conflated, because
    // ChapterReader looks the chapter up by the decoded name.
    test(
        'TC-CNT-6 [Boundary]: a percent-encoded href keys raw and stores a '
        'decoded fileName', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildBookWithEveryMediaType());

      expect(
          bookRef.content!.html!['ch%20one.xhtml']!.fileName, 'ch one.xhtml');
      expect(bookRef.content!.images!['a.png']!.contentMimeType, 'image/png');
      expect(
        bookRef.content!.images!['a.png']!.contentType,
        EpubContentType.imagePng,
      );
    });

    // TC-CNT-7 [Scenario/use-case]: every manifest item ends up in allFiles
    // exactly once, whichever branch it took.
    test('TC-CNT-7 [Scenario]: allFiles holds one entry per manifest item',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildBookWithEveryMediaType());

      expect(
        bookRef.content!.allFiles!.keys.length,
        bookRef.schema!.package!.manifest!.items!.length,
      );
    });
  });
}
