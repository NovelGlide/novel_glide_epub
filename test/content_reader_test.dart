// `ContentReader` — the manifest-to-content-map sorter.
//
// Two halves: the mime-type table (`getContentTypeByContentMimeType`) and the
// bucketing of manifest items into html / css / images / fonts / allFiles,
// each keyed by the item's DECODED href. The bucketing is exercised both
// through a real `EpubReader.openBook`, which is how a caller reaches it, and
// by calling `parseContentMap` on a hand-built manifest, which isolates the
// key rules (decoding, collisions) from every other reader.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/readers/content_reader.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_byte_content_file_ref.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_content_file_ref.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_content_ref.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_text_content_file_ref.dart';
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
    // document, XML, OEB1 CSS) appear only in allFiles — but still as TEXT
    // refs, since each of them is a text format.
    test('TC-CNT-4 [Scenario]: text items are bucketed into html and css',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildBookWithEveryMediaType());
      final EpubContentRef content = bookRef.content;

      expect(content.html.keys, <String>[
        'chapter1.xhtml',
        'chapter2.html',
        'ch one.xhtml',
      ]);
      expect(content.css.keys, <String>['styles.css']);
      for (final String textFile in <String>[
        'chapter1.xhtml',
        'chapter2.html',
        'ch one.xhtml',
        'styles.css',
        'toc.ncx',
        'book.dtbook',
        'legacy.html',
        'data.xml',
        'legacy.css',
      ]) {
        expect(content.allFiles[textFile], isA<EpubTextContentFileRef>(),
            reason: '$textFile is a text format');
      }
    });

    // TC-CNT-5 [Scenario/use-case]: byte-shaped items split into images,
    // fonts, and the `EpubContentType.other` remainder that lands in
    // allFiles only.
    test('TC-CNT-5 [Scenario]: byte items are bucketed into images and fonts',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildBookWithEveryMediaType());
      final EpubContentRef content = bookRef.content;

      expect(
        content.images.keys,
        <String>['a.gif', 'a.jpg', 'a.png', 'a.svg', 'a.bmp'],
      );
      expect(content.fonts.keys, <String>['a.ttf', 'a.otf', 'ms.otf']);
      for (final String byteFile in <String>[
        'a.gif',
        'a.jpg',
        'a.png',
        'a.svg',
        'a.bmp',
        'a.ttf',
        'a.otf',
        'ms.otf',
        'a.bin',
      ]) {
        expect(content.allFiles[byteFile], isA<EpubByteContentFileRef>(),
            reason: '$byteFile is not a text format');
      }
    });

    // TC-CNT-6 [Boundary value]: a percent-encoded href is keyed by its
    // DECODED name, the same string as the ref's fileName — a navigation
    // link, decoded the same way, finds it however either side spelled it.
    // The escaped spelling is not a key at all.
    test(
        'TC-CNT-6 [Boundary]: a percent-encoded href keys and names the file '
        'decoded', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildBookWithEveryMediaType());

      expect(bookRef.content.html['ch one.xhtml']!.fileName, 'ch one.xhtml');
      expect(bookRef.content.html.containsKey('ch%20one.xhtml'), isFalse);
      expect(bookRef.content.allFiles.containsKey('ch%20one.xhtml'), isFalse);
      expect(bookRef.content.images['a.png']!.contentMimeType, 'image/png');
      expect(
        bookRef.content.images['a.png']!.contentType,
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
        bookRef.content.allFiles.keys.length,
        bookRef.schema.package.manifest.items.length,
      );
    });

    // TC-CNT-8 [Scenario/use-case]: a manifest that escapes non-ASCII names
    // is keyed by the raw names, and each ref reads its entry from the given
    // archive under the given content directory.
    test(
        'TC-CNT-8 [Scenario]: escaped non-ASCII hrefs are keyed decoded and '
        'read from the archive', () async {
      final Archive archive = Archive()
        ..addFile(ArchiveFile.string(
            'OEBPS/第一章.xhtml', seedXhtml('NGE-SEED-CJK-CH1')))
        ..addFile(ArchiveFile('OEBPS/圖 一.png', 3, <int>[0x4E, 0x47, 0x45]));

      final EpubContentRef content = const ContentReader().parseContentMap(
        archive,
        'OEBPS',
        const EpubManifest(items: <EpubManifestItem>[
          EpubManifestItem(
            id: 'ch1',
            href: '%E7%AC%AC%E4%B8%80%E7%AB%A0.xhtml',
            mediaType: 'application/xhtml+xml',
          ),
          EpubManifestItem(
            id: 'img',
            href: '%E5%9C%96%20%E4%B8%80.png',
            mediaType: 'image/png',
          ),
        ]),
      );

      expect(content.html.keys, <String>['第一章.xhtml']);
      expect(content.images.keys, <String>['圖 一.png']);
      expect(content.allFiles.keys, <String>['第一章.xhtml', '圖 一.png']);
      expect(content.css, isEmpty);
      expect(content.fonts, isEmpty);
      final EpubTextContentFileRef chapter = content.html['第一章.xhtml']!;
      expect(chapter.fileName, '第一章.xhtml');
      expect(chapter.contentMimeType, 'application/xhtml+xml');
      expect(chapter.contentType, EpubContentType.xhtml11);
      expect(await chapter.readContentAsText(), contains('NGE-SEED-CJK-CH1'));
      expect(await content.images['圖 一.png']!.readContentAsBytes(),
          <int>[0x4E, 0x47, 0x45]);
    });

    // TC-CNT-9 [Error guessing]: two manifest items whose hrefs decode to one
    // name name one archive entry, so they share one key; the LATER item's
    // ref is kept, whichever of the two spellings came first.
    for (final List<String> row in <List<String>>[
      <String>['ch%20one.xhtml', 'ch one.xhtml'],
      <String>['ch one.xhtml', 'ch%20one.xhtml'],
    ]) {
      test(
          'TC-CNT-9 [Error guessing]: "${row[0]}" then "${row[1]}" keep one '
          'entry, the later', () {
        final EpubContentRef content = const ContentReader().parseContentMap(
          Archive(),
          'OEBPS',
          EpubManifest(items: <EpubManifestItem>[
            EpubManifestItem(
              id: 'first',
              href: row[0],
              mediaType: 'application/xhtml+xml',
            ),
            EpubManifestItem(
              id: 'later',
              href: row[1],
              mediaType: 'text/html',
            ),
          ]),
        );

        expect(content.html.keys, <String>['ch one.xhtml']);
        expect(content.allFiles.keys, <String>['ch one.xhtml']);
        expect(content.html['ch one.xhtml']!.contentMimeType, 'text/html');
        expect(content.allFiles['ch one.xhtml']!.contentMimeType, 'text/html');
      });
    }

    // TC-CNT-12 [Error guessing]: when the two items that share a decoded
    // name have media types filed in different buckets, the earlier item
    // leaves no trace in its own bucket: every map agrees on the one file.
    test(
        'TC-CNT-12 [Error guessing]: a later item of another media type '
        'replaces the earlier one in every map', () {
      final EpubContentRef content = const ContentReader().parseContentMap(
        Archive(),
        'OEBPS',
        const EpubManifest(items: <EpubManifestItem>[
          EpubManifestItem(
            id: 'first',
            href: 'NGE-SEED%20page.png',
            mediaType: 'image/png',
          ),
          EpubManifestItem(
            id: 'later',
            href: 'NGE-SEED page.png',
            mediaType: 'application/xhtml+xml',
          ),
        ]),
      );

      expect(content.images, isEmpty);
      expect(content.html.keys, <String>['NGE-SEED page.png']);
      expect(content.allFiles.keys, <String>['NGE-SEED page.png']);
      expect(content.allFiles['NGE-SEED page.png'],
          same(content.html['NGE-SEED page.png']));
    });

    // TC-CNT-10 [Boundary value]: an empty manifest yields five empty maps,
    // not null ones.
    test('TC-CNT-10 [Boundary]: an empty manifest yields empty maps', () {
      final EpubContentRef content = const ContentReader().parseContentMap(
        Archive(),
        '',
        const EpubManifest(items: <EpubManifestItem>[]),
      );

      expect(content.html, isEmpty);
      expect(content.css, isEmpty);
      expect(content.images, isEmpty);
      expect(content.fonts, isEmpty);
      expect(content.allFiles, isEmpty);
    });

    // TC-CNT-11 [Scenario/use-case]: `allFiles` shares each bucketed ref
    // rather than holding a second copy, so either map reaches the same
    // file.
    test('TC-CNT-11 [Scenario]: allFiles shares the bucketed refs', () async {
      final EpubContentRef content =
          (await const EpubReader().openBook(_buildBookWithEveryMediaType()))
              .content;

      for (final MapEntry<String, EpubContentFileRef> entry
          in <MapEntry<String, EpubContentFileRef>>[
        ...content.html.entries,
        ...content.css.entries,
        ...content.images.entries,
        ...content.fonts.entries,
      ]) {
        expect(identical(content.allFiles[entry.key], entry.value), isTrue,
            reason: entry.key);
      }
    });
  });
}
