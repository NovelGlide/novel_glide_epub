// `EpubReader` — the package's entry point, both modes.
//
// `openBook` keeps the archive handle and loads metadata only; `readBook`
// pulls every file into memory. The eager mode is what fans out into
// readContent / readTextContentFiles / readByteContentFiles / readChapters,
// so one full-fat fixture exercises the whole fan-out and the assertions name
// what each stage is responsible for.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

const List<int> _seedFontBytes = <int>[0x00, 0x01, 0x00, 0x00, 0x4E, 0x47];
const List<int> _seedBlobBytes = <int>[0x4E, 0x47, 0x45, 0x2D, 0x53, 0x45];

const String _ncx = '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-READBOOK"/></head>'
    '<docTitle><text>NGE-SEED Read Book</text></docTitle>'
    '<navMap>'
    '<navPoint id="np-1" playOrder="1">'
    '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
    '<content src="chapter1.xhtml"/>'
    '<navPoint id="np-1-1" playOrder="2">'
    '<navLabel><text>NGE-SEED Section 1.1</text></navLabel>'
    '<content src="chapter2.xhtml#sec-1-1"/>'
    '</navPoint>'
    '</navPoint>'
    '</navMap>'
    '</ncx>';

/// A book carrying one of every content shape `readContent` fans out over:
/// html, css, an image, a font, and an unclassified blob.
Uint8List _buildFullBook() => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:NGE-SEED-READBOOK'
            '</dc:identifier>'
            '<dc:title>NGE-SEED Read Book</dc:title>'
            '<dc:creator>NGE-SEED Author One</dc:creator>'
            '<dc:creator>NGE-SEED Author Two</dc:creator>'
            '<dc:language>en</dc:language>'
            '<meta name="cover" content="cover-img"/>'
            '</metadata>'
            '<manifest>'
            '<item id="ncx" href="toc.ncx" '
            'media-type="application/x-dtbncx+xml"/>'
            '<item id="ch1" href="chapter1.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<item id="ch2" href="chapter2.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<item id="css" href="styles.css" media-type="text/css"/>'
            '<item id="cover-img" href="cover.png" media-type="image/png"/>'
            '<item id="font" href="seed.ttf" media-type="font/truetype"/>'
            '<item id="blob" href="seed.bin" '
            'media-type="application/octet-stream"/>'
            '</manifest>'
            '<spine toc="ncx">'
            '<itemref idref="ch1"/><itemref idref="ch2"/>'
            '</spine>'
            '</package>',
        'OEBPS/toc.ncx': _ncx,
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
        'OEBPS/chapter2.xhtml': seedXhtml('NGE-SEED-CH2'),
        'OEBPS/styles.css': 'body { color: #NGESEED; }',
      },
      binaryEntries: <String, List<int>>{
        'OEBPS/cover.png': seedPngBytes(),
        'OEBPS/seed.ttf': _seedFontBytes,
        'OEBPS/seed.bin': _seedBlobBytes,
      },
    );

void main() {
  group('EpubReader.openBook', () {
    // TC-RDR-1 [Scenario/use-case]: opening lifts title and author list off
    // the metadata without reading any content file.
    test(
        'TC-RDR-1 [Scenario]: opening a book lifts title and authors from '
        'metadata', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildFullBook());

      expect(bookRef.title, 'NGE-SEED Read Book');
      expect(bookRef.authorList,
          <String>['NGE-SEED Author One', 'NGE-SEED Author Two']);
      expect(bookRef.author, 'NGE-SEED Author One, NGE-SEED Author Two');
      expect(bookRef.content!.html!.keys, hasLength(2));
    });

    // TC-RDR-2 [Equivalence partitioning]: the bytes argument accepts both a
    // plain list and a Future — the app hands over the result of an async
    // file read, so the Future arm is the one it actually uses.
    test(
        'TC-RDR-2 [Equivalence partitioning]: openBook accepts a Future of '
        'bytes as well as a list', () async {
      final EpubBookRef fromFuture = await const EpubReader()
          .openBook(Future<List<int>>.value(_buildFullBook()));

      expect(fromFuture.title, 'NGE-SEED Read Book');
    });

    // TC-RDR-3 [Boundary value]: a book whose metadata declares no creator
    // gets an empty author list and an empty joined author, not null.
    test(
        'TC-RDR-3 [Boundary]: a book with no creator has an empty author '
        'string', () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
              '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
              'unique-identifier="uid">'
              '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
              '<dc:identifier id="uid">urn:uuid:NGE-SEED-NOAUTHOR'
              '</dc:identifier>'
              '<dc:title>NGE-SEED No Author</dc:title>'
              '</metadata>'
              '<manifest>'
              '<item id="ncx" href="toc.ncx" '
              'media-type="application/x-dtbncx+xml"/>'
              '<item id="ch1" href="chapter1.xhtml" '
              'media-type="application/xhtml+xml"/>'
              '</manifest>'
              '<spine toc="ncx"><itemref idref="ch1"/></spine>'
              '</package>',
          'OEBPS/toc.ncx': _ncx.replaceFirst(
            '<navPoint id="np-1-1" playOrder="2">'
                '<navLabel><text>NGE-SEED Section 1.1</text></navLabel>'
                '<content src="chapter2.xhtml#sec-1-1"/>'
                '</navPoint>',
            '',
          ),
          'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
        },
      );

      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);

      expect(bookRef.authorList, isEmpty);
      expect(bookRef.author, isEmpty);
    });
  });

  group('EpubReader.readBook', () {
    // TC-RDR-4 [Scenario/use-case]: the eager read carries the same metadata
    // as the lazy open, plus the decoded cover.
    test(
        'TC-RDR-4 [Scenario]: reading a book carries metadata and decodes '
        'the cover', () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      expect(book.title, 'NGE-SEED Read Book');
      expect(book.author, 'NGE-SEED Author One, NGE-SEED Author Two');
      expect(book.schema!.package!.version, EpubVersion.epub2);
      expect(book.coverImage, isNotNull);
      expect(book.coverImage!.width, 2);
    });

    // TC-RDR-5 [Scenario/use-case]: text content files are materialised as
    // decoded strings in their own buckets.
    test('TC-RDR-5 [Scenario]: html and css are materialised as decoded text',
        () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      final EpubTextContentFile chapter =
          book.content!.html!['chapter1.xhtml']!;
      expect(chapter.content, contains('NGE-SEED-CH1'));
      expect(chapter.fileName, 'chapter1.xhtml');
      expect(chapter.contentType, EpubContentType.xhtml11);
      expect(chapter.contentMimeType, 'application/xhtml+xml');
      expect(book.content!.css!['styles.css']!.content,
          'body { color: #NGESEED; }');
    });

    // TC-RDR-6 [Scenario/use-case]: byte content files are materialised as
    // raw bytes, images and fonts alike.
    test('TC-RDR-6 [Scenario]: images and fonts are materialised as bytes',
        () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      expect(book.content!.images!['cover.png']!.content, seedPngBytes());
      expect(book.content!.fonts!['seed.ttf']!.content, _seedFontBytes);
      expect(
        book.content!.fonts!['seed.ttf']!.contentType,
        EpubContentType.fontTruetype,
      );
      // `readByteContentFile` copies three fields off the ref besides
      // content; only contentType was ever asserted above contentType.
      expect(book.content!.fonts!['seed.ttf']!.fileName, 'seed.ttf');
      expect(
        book.content!.fonts!['seed.ttf']!.contentMimeType,
        'font/truetype',
      );
    });

    // TC-RDR-7 [Equivalence partitioning]: allFiles is the union — the
    // bucketed files plus the ones no bucket claimed (here the NCX and an
    // octet-stream blob), which are read as bytes on the way in.
    test(
        'TC-RDR-7 [Equivalence partitioning]: allFiles unions bucketed and '
        'unbucketed files', () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      expect(
        book.content!.allFiles!.keys,
        containsAll(<String>[
          'chapter1.xhtml',
          'chapter2.xhtml',
          'styles.css',
          'cover.png',
          'seed.ttf',
          'toc.ncx',
          'seed.bin',
        ]),
      );
      expect(
        (book.content!.allFiles!['seed.bin']! as EpubByteContentFile).content,
        _seedBlobBytes,
      );
      // The NCX is a text type with no bucket, so allFiles picks it up
      // through the byte-reading fallback rather than the text pass.
      expect(
        book.content!.allFiles!['toc.ncx'],
        isA<EpubByteContentFile>(),
      );
    });

    // TC-RDR-8 [Scenario/use-case]: chapters are materialised recursively,
    // each with its html already read.
    test(
        'TC-RDR-8 [Scenario]: chapters are materialised recursively with '
        'their html', () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      expect(book.chapters, hasLength(1));
      final EpubChapter chapter = book.chapters!.single;
      expect(chapter.title, 'NGE-SEED Chapter One');
      expect(chapter.contentFileName, 'chapter1.xhtml');
      expect(chapter.anchor, isNull);
      expect(chapter.htmlContent, contains('NGE-SEED-CH1'));

      final EpubChapter sub = chapter.subChapters!.single;
      expect(sub.title, 'NGE-SEED Section 1.1');
      expect(sub.anchor, 'sec-1-1');
      expect(sub.htmlContent, contains('NGE-SEED-CH2'));
      expect(sub.subChapters, isEmpty);
    });

    // TC-RDR-9 [Equivalence partitioning]: readBook takes a Future of bytes
    // too, on its own code path rather than openBook's.
    test(
        'TC-RDR-9 [Equivalence partitioning]: readBook accepts a Future of '
        'bytes', () async {
      final EpubBook book = await const EpubReader()
          .readBook(Future<List<int>>.value(_buildFullBook()));

      expect(book.title, 'NGE-SEED Read Book');
    });

    // TC-RDR-10 [Scenario/use-case]: `allFiles` is not just a union of KEYS
    // (TC-RDR-7 already covers that) — for every file a typed bucket claims,
    // the `allFiles` entry must be the SAME object as the bucketed one, not a
    // second, independently byte-read copy. That is the one thing the
    // fallback loop over `contentRef.allFiles` cannot produce on its own,
    // since it only fills keys the typed passes left untouched.
    test(
        'TC-RDR-10 [Scenario]: allFiles shares the bucketed instance for '
        'html, css, images and fonts', () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      expect(
        identical(
          book.content!.allFiles!['chapter1.xhtml'],
          book.content!.html!['chapter1.xhtml'],
        ),
        isTrue,
      );
      expect(
        identical(
          book.content!.allFiles!['styles.css'],
          book.content!.css!['styles.css'],
        ),
        isTrue,
      );
      expect(
        identical(
          book.content!.allFiles!['cover.png'],
          book.content!.images!['cover.png'],
        ),
        isTrue,
      );
      expect(
        identical(
          book.content!.allFiles!['seed.ttf'],
          book.content!.fonts!['seed.ttf'],
        ),
        isTrue,
      );
    });
  });
}
