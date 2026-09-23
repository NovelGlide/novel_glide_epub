// `EpubReader` — the package's entry point, both modes.
//
// `openBook` keeps the archive handle and loads metadata only; `readBook`
// pulls every file into memory. The eager mode is what fans out into
// readContent / readTextContentFiles / readByteContentFiles / readChapters,
// so one full-fat fixture exercises the whole fan-out and the assertions name
// what each stage is responsible for.
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

/// A one-chapter EPUB2 book whose `<metadata>` holds only [metadata], its
/// package document and files under [directory] (the archive root when
/// empty). The chapter's manifest href is [chapterHref]; its archive entry is
/// always the raw `chapter one.xhtml`.
Uint8List _buildBareBook({
  required String metadata,
  String directory = 'OEBPS',
  String chapterHref = 'chapter one.xhtml',
}) {
  final String prefix = directory.isEmpty ? '' : '$directory/';
  return buildEpubArchive(
    opfPath: '${prefix}content.opf',
    textEntries: <String, String>{
      '${prefix}content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
          '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
          'unique-identifier="uid">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '$metadata'
          '</metadata>'
          '<manifest>'
          '<item id="ncx" href="toc.ncx" '
          'media-type="application/x-dtbncx+xml"/>'
          '<item id="ch1" href="$chapterHref" '
          'media-type="application/xhtml+xml"/>'
          '</manifest>'
          '<spine toc="ncx"><itemref idref="ch1"/></spine>'
          '</package>',
      '${prefix}toc.ncx': '<?xml version="1.0" encoding="UTF-8"?>'
          '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
          '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-BARE"/></head>'
          '<docTitle><text>NGE-SEED Bare Book</text></docTitle>'
          '<navMap><navPoint id="np-1" playOrder="1">'
          '<navLabel><text>NGE-SEED Bare Chapter</text></navLabel>'
          '<content src="$chapterHref"/>'
          '</navPoint></navMap>'
          '</ncx>',
      '${prefix}chapter one.xhtml': seedXhtml('NGE-SEED-BARE-CH1'),
    },
  );
}

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
      expect(bookRef.content.html.keys,
          <String>['chapter1.xhtml', 'chapter2.xhtml']);
      expect(bookRef.schema.contentDirectoryPath, 'OEBPS');
      expect(bookRef.schema.package.version, EpubVersion.epub2);
      expect(
        bookRef.schema.navigation.navMap.points.single.navigationLabels.single
            .text,
        'NGE-SEED Chapter One',
      );
      // The handle the lazy refs read through is the book's own archive.
      expect(
        bookRef.epubArchive().files.map((ArchiveFile file) => file.name),
        containsAll(<String>['OEBPS/content.opf', 'OEBPS/chapter1.xhtml']),
      );
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
    // gets an empty author list, not null.
    test(
        'TC-RDR-3 [Boundary]: a book with no creator has an empty author '
        'list', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildBareBook(metadata: '<dc:title>NGE-SEED No Author</dc:title>'),
      );

      expect(bookRef.title, 'NGE-SEED No Author');
      expect(bookRef.authorList, isEmpty);
    });

    // TC-RDR-11 [Boundary value]: OPF requires a `dc:title`, but a book
    // without one still opens, with an empty title rather than a throw.
    test('TC-RDR-11 [Boundary]: a book with no title has an empty title',
        () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildBareBook(metadata: '<dc:creator>NGE-SEED Author</dc:creator>'),
      );

      expect(bookRef.title, '');
      expect(bookRef.authorList, <String>['NGE-SEED Author']);
    });

    // TC-RDR-12 [Equivalence partitioning]: of several titles the first is
    // the book's title; every creator is kept, in document order.
    test(
        'TC-RDR-12 [Equivalence partitioning]: the first of several titles '
        'is the title', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildBareBook(
          metadata: '<dc:title>NGE-SEED Main</dc:title>'
              '<dc:creator>NGE-SEED Zed</dc:creator>'
              '<dc:title>NGE-SEED Subtitle</dc:title>'
              '<dc:creator>NGE-SEED Abe</dc:creator>',
        ),
      );

      expect(bookRef.title, 'NGE-SEED Main');
      expect(bookRef.authorList, <String>['NGE-SEED Zed', 'NGE-SEED Abe']);
    });

    // TC-RDR-13 [Boundary value]: an OPF at the archive root gives an empty
    // content directory, and the content files resolve from the root.
    test(
        'TC-RDR-13 [Boundary]: a package document at the archive root reads '
        'its files from the root', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildBareBook(
          metadata: '<dc:title>NGE-SEED Root</dc:title>',
          directory: '',
        ),
      );

      expect(bookRef.schema.contentDirectoryPath, '');
      final EpubChapterRef chapter = (await bookRef.getChapters()).single;
      expect(await chapter.readHtmlContent(), contains('NGE-SEED-BARE-CH1'));
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
      expect(book.authorList,
          <String>['NGE-SEED Author One', 'NGE-SEED Author Two']);
      expect(book.schema.package.version, EpubVersion.epub2);
      expect(book.coverImage, isNotNull);
      expect(book.coverImage!.width, 2);
    });

    // TC-RDR-5 [Scenario/use-case]: text content files are materialised as
    // decoded strings in their own buckets.
    test('TC-RDR-5 [Scenario]: html and css are materialised as decoded text',
        () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      final EpubTextContentFile chapter = book.content.html['chapter1.xhtml']!;
      expect(chapter.content, contains('NGE-SEED-CH1'));
      expect(chapter.fileName, 'chapter1.xhtml');
      expect(chapter.contentType, EpubContentType.xhtml11);
      expect(chapter.contentMimeType, 'application/xhtml+xml');
      expect(
          book.content.css['styles.css']!.content, 'body { color: #NGESEED; }');
    });

    // TC-RDR-6 [Scenario/use-case]: byte content files are materialised as
    // raw bytes, images and fonts alike.
    test('TC-RDR-6 [Scenario]: images and fonts are materialised as bytes',
        () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      expect(book.content.images['cover.png']!.content, seedPngBytes());
      expect(book.content.fonts['seed.ttf']!.content, _seedFontBytes);
      expect(
        book.content.fonts['seed.ttf']!.contentType,
        EpubContentType.fontTruetype,
      );
      // `readByteContentFile` copies three fields off the ref besides
      // content; only contentType was ever asserted above contentType.
      expect(book.content.fonts['seed.ttf']!.fileName, 'seed.ttf');
      expect(
        book.content.fonts['seed.ttf']!.contentMimeType,
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
        book.content.allFiles.keys,
        unorderedEquals(<String>[
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
        book.content.allFiles['seed.bin'],
        isA<EpubByteContentFile>()
            .having((EpubByteContentFile file) => file.content, 'content',
                _seedBlobBytes)
            .having((EpubByteContentFile file) => file.contentMimeType,
                'contentMimeType', 'application/octet-stream')
            .having((EpubByteContentFile file) => file.contentType,
                'contentType', EpubContentType.other),
      );
      // The NCX is a text type with no bucket, so allFiles picks it up
      // through the byte-reading fallback rather than the text pass.
      expect(
        book.content.allFiles['toc.ncx'],
        isA<EpubByteContentFile>()
            .having((EpubByteContentFile file) => file.content, 'content',
                _ncx.codeUnits)
            .having((EpubByteContentFile file) => file.fileName, 'fileName',
                'toc.ncx'),
      );
    });

    // TC-RDR-8 [Scenario/use-case]: chapters are materialised recursively,
    // each with its html already read.
    test(
        'TC-RDR-8 [Scenario]: chapters are materialised recursively with '
        'their html', () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      expect(book.chapters, hasLength(1));
      final EpubChapter chapter = book.chapters.single;
      expect(chapter.title, 'NGE-SEED Chapter One');
      expect(chapter.contentFileName, 'chapter1.xhtml');
      expect(chapter.anchor, isNull);
      expect(chapter.htmlContent, contains('NGE-SEED-CH1'));

      final EpubChapter sub = chapter.subChapters.single;
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
          book.content.allFiles['chapter1.xhtml'],
          book.content.html['chapter1.xhtml'],
        ),
        isTrue,
      );
      expect(
        identical(
          book.content.allFiles['styles.css'],
          book.content.css['styles.css'],
        ),
        isTrue,
      );
      expect(
        identical(
          book.content.allFiles['cover.png'],
          book.content.images['cover.png'],
        ),
        isTrue,
      );
      expect(
        identical(
          book.content.allFiles['seed.ttf'],
          book.content.fonts['seed.ttf'],
        ),
        isTrue,
      );
    });

    // TC-RDR-14 [Scenario/use-case]: every field `readBook` fills comes from
    // the same opened book: title, author list and schema as `openBook`
    // reads them, and one content file per content ref under the same key.
    test(
        'TC-RDR-14 [Scenario]: readBook carries what openBook reads, key for '
        'key', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildFullBook());
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());

      expect(book.title, bookRef.title);
      expect(book.authorList, bookRef.authorList);
      expect(book.schema, bookRef.schema);
      expect(book.schema.contentDirectoryPath, 'OEBPS');
      expect(book.content.html.keys, bookRef.content.html.keys);
      expect(book.content.css.keys, bookRef.content.css.keys);
      expect(book.content.images.keys, bookRef.content.images.keys);
      expect(book.content.fonts.keys, bookRef.content.fonts.keys);
      expect(book.content.allFiles.keys,
          unorderedEquals(bookRef.content.allFiles.keys));
    });

    // TC-RDR-15 [Boundary value]: a book with no title, no creator and no
    // cover reads as an empty title, an empty author list and a null cover —
    // the eager mode fills the same defaults as the lazy one.
    test(
        'TC-RDR-15 [Boundary]: a bare book reads an empty title, no authors '
        'and no cover', () async {
      final EpubBook book = await const EpubReader().readBook(
        _buildBareBook(metadata: '<dc:language>en</dc:language>'),
      );

      expect(book.title, '');
      expect(book.authorList, isEmpty);
      expect(book.coverImage, isNull);
      expect(book.chapters.single.title, 'NGE-SEED Bare Chapter');
    });

    // TC-RDR-16 [Regression]: a manifest that escapes a name keys the read
    // content by the decoded name, as the refs are, and the chapter is read
    // under that same name.
    test(
        'TC-RDR-16 [Regression]: read content is keyed by the decoded file '
        'name', () async {
      final EpubBook book = await const EpubReader().readBook(
        _buildBareBook(
          metadata: '<dc:title>NGE-SEED Escaped</dc:title>',
          chapterHref: 'chapter%20one.xhtml',
        ),
      );

      expect(book.content.html.keys, <String>['chapter one.xhtml']);
      expect(book.content.html['chapter one.xhtml']!.fileName,
          'chapter one.xhtml');
      expect(book.content.allFiles.keys,
          unorderedEquals(<String>['chapter one.xhtml', 'toc.ncx']));
      final EpubChapter chapter = book.chapters.single;
      expect(chapter.contentFileName, 'chapter one.xhtml');
      expect(chapter.htmlContent, contains('NGE-SEED-BARE-CH1'));
    });

    // TC-RDR-17 [Scenario/use-case]: a chapter the producer split into
    // `_split_` files carries the names of its other parts into the loaded
    // chapter, and its html joins every part in manifest order.
    test(
        'TC-RDR-17 [Scenario]: a split chapter keeps the names of its other '
        'parts', () async {
      final EpubBook book =
          await const EpubReader().readBook(_buildSplitBook());

      final EpubChapter chapter = book.chapters.single;
      expect(chapter.contentFileName, 'part_split_000.xhtml');
      expect(chapter.otherContentFileNames, <String>['part_split_001.xhtml']);
      expect(
          chapter.htmlContent, '<p>NGE-SEED-PART-A</p><p>NGE-SEED-PART-B</p>');
    });

    // TC-RDR-18 [Error guessing]: every list and map a reader hands to an
    // entity is unmodifiable, so an entity cannot change after it is built —
    // its hash code included.
    test(
        'TC-RDR-18 [Error guessing]: the collections a read book holds '
        'cannot be changed', () async {
      final EpubBook book = await const EpubReader().readBook(_buildFullBook());
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildFullBook());

      expect(() => book.authorList.add('NGE-SEED'), throwsUnsupportedError);
      expect(() => book.chapters.clear(), throwsUnsupportedError);
      expect(() => book.chapters.single.subChapters.clear(),
          throwsUnsupportedError);
      expect(() => book.content.html.clear(), throwsUnsupportedError);
      expect(() => book.content.allFiles.clear(), throwsUnsupportedError);
      expect(() => bookRef.content.images.clear(), throwsUnsupportedError);
      expect(() => bookRef.schema.package.metadata.titles.clear(),
          throwsUnsupportedError);
      expect(
          () => bookRef.schema.package.metadata.metaItems.first.attributes
              .clear(),
          throwsUnsupportedError);
      expect(
          () => bookRef.schema.navigation.navMap.points.first.navigationLabels
              .clear(),
          throwsUnsupportedError);
    });
  });
}

/// One chapter split across two `_split_` files, which the NCX names by its
/// first part only.
Uint8List _buildSplitBook() => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:title>NGE-SEED Split Book</dc:title>'
            '</metadata>'
            '<manifest>'
            '<item id="ncx" href="toc.ncx" '
            'media-type="application/x-dtbncx+xml"/>'
            '<item id="p0" href="part_split_000.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<item id="p1" href="part_split_001.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine toc="ncx"><itemref idref="p0"/><itemref idref="p1"/>'
            '</spine>'
            '</package>',
        'OEBPS/toc.ncx': '<?xml version="1.0" encoding="UTF-8"?>'
            '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" '
            'version="2005-1">'
            '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-SPLIT"/>'
            '</head>'
            '<docTitle><text>NGE-SEED Split Book</text></docTitle>'
            '<navMap><navPoint id="np-1" playOrder="1">'
            '<navLabel><text>NGE-SEED Split Chapter</text></navLabel>'
            '<content src="part_split_000.xhtml"/>'
            '</navPoint></navMap>'
            '</ncx>',
        'OEBPS/part_split_000.xhtml': '<p>NGE-SEED-PART-A</p>',
        'OEBPS/part_split_001.xhtml': '<p>NGE-SEED-PART-B</p>',
      },
    );
