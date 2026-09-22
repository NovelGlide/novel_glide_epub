// The lazy, archive-backed `*Ref` entities — `EpubBookRef`, `EpubContentRef`,
// `EpubContentFileRef` and its two subclasses, and `EpubChapterRef`.
//
// Unlike the plain entities, these hold a live `Archive` handle and read from
// it on demand, so every fixture here is built through the public entry point
// `EpubReader.openBook`. Refs are never constructed by hand: their constructor
// arguments are reader-owned, and a hand-built ref would be asserting a shape
// the reader does not actually produce.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_byte_content_file_ref.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_content_ref.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_text_content_file_ref.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

const String _manifestItems = '<item id="ncx" href="toc.ncx" '
    'media-type="application/x-dtbncx+xml"/>'
    '<item id="ch1" href="chapter1.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '<item id="css" href="style.css" media-type="text/css"/>'
    '<item id="cover" href="cover.png" media-type="image/png"/>'
    '<item id="font" href="body.ttf" media-type="font/truetype"/>';

String _opf({String manifestItems = _manifestItems, String coverMeta = ''}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
    'unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>NGE-SEED Ref Book</dc:title>'
    '<dc:creator>NGE-SEED Author One</dc:creator>'
    '<dc:creator>NGE-SEED Author Two</dc:creator>'
    '$coverMeta'
    '</metadata>'
    '<manifest>$manifestItems</manifest>'
    '<spine toc="ncx"><itemref idref="ch1"/></spine>'
    '</package>';

String _ncx({String navPoints = ''}) => '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-REF"/></head>'
    '<docTitle><text>NGE-SEED Ref Book</text></docTitle>'
    '<navMap>'
    '${navPoints.isEmpty ? '<navPoint id="np-1" playOrder="1">'
        '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
        '<content src="chapter1.xhtml"/>'
        '</navPoint>' : navPoints}'
    '</navMap>'
    '</ncx>';

/// The standard fixture: one chapter, one stylesheet, one image, one font.
Uint8List seedArchive({String chapterBody = 'NGE-SEED-CH1'}) =>
    buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': _opf(),
        'OEBPS/toc.ncx': _ncx(),
        'OEBPS/chapter1.xhtml': seedXhtml(chapterBody),
        'OEBPS/style.css': 'body { color: #000; }',
      },
      binaryEntries: <String, List<int>>{
        'OEBPS/cover.png': seedPngBytes(),
        'OEBPS/body.ttf': <int>[0, 1, 0, 0, 78, 71, 69],
      },
    );

/// A book whose single chapter is split across two files, which is the only
/// shape that populates `EpubChapterRef.otherTextContentFileRefs` — the
/// reader triggers on the `_split_` marker in the href.
Uint8List seedSplitChapterArchive() => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': _opf(
          manifestItems: '<item id="ncx" href="toc.ncx" '
              'media-type="application/x-dtbncx+xml"/>'
              '<item id="p0" href="part_split_000.xhtml" '
              'media-type="application/xhtml+xml"/>'
              '<item id="p1" href="part_split_001.xhtml" '
              'media-type="application/xhtml+xml"/>',
        ),
        'OEBPS/toc.ncx': _ncx(
          navPoints: '<navPoint id="np-1" playOrder="1">'
              '<navLabel><text>NGE-SEED Split Chapter</text></navLabel>'
              '<content src="part_split_000.xhtml"/>'
              '</navPoint>',
        ),
        'OEBPS/part_split_000.xhtml': '<p>NGE-SEED-PART-A</p>',
        'OEBPS/part_split_001.xhtml': '<p>NGE-SEED-PART-B</p>',
      },
    );

/// An operand of an unrelated type, held as `Object` so each comparison below
/// is a real runtime check. Typing it `Object` rather than inlining a literal
/// is what keeps these tests free of an `unrelated_type_equality_checks`
/// suppression, which this package's lint forbids outright.
const Object unrelatedOperand = 'NGE-SEED-not-a-domain-object';

/// A null operand, typed nullable so the analyzer does not fold the comparison
/// away as a statically-known mismatch. Every class under test must answer
/// false here rather than throw.
const Object? nullOperand = null;

void main() {
  group('EpubBookRef', () {
    // TC-REF-1 [Scenario/use-case]: the metadata the ref exposes without
    // reading any content, and the archive handle it keeps open.
    test(
        'TC-REF-1 [Scenario]: an opened book exposes title, authors and its '
        'archive', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());

      expect(bookRef.title, 'NGE-SEED Ref Book');
      expect(bookRef.authorList,
          <String>['NGE-SEED Author One', 'NGE-SEED Author Two']);
      expect(bookRef.author, 'NGE-SEED Author One, NGE-SEED Author Two');
      expect(bookRef.schema!.contentDirectoryPath, 'OEBPS');
      expect(bookRef.epubArchive(), isA<Archive>());
      expect(
        bookRef.epubArchive()!.files.map((ArchiveFile f) => f.name),
        contains('OEBPS/chapter1.xhtml'),
      );
    });

    // TC-REF-2 [Scenario/use-case]: two opens of one archive produce refs that
    // agree on `==` and `hashCode` — the whole equality chain, since every
    // field the ref compares is reader-populated.
    test('TC-REF-2 [Scenario]: two opens of one archive are equal', () async {
      final Uint8List bytes = seedArchive();
      final EpubBookRef first = await const EpubReader().openBook(bytes);
      final EpubBookRef second = await const EpubReader().openBook(bytes);

      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
    });

    // TC-REF-3 [Equivalence partitioning]: each compared field decides once.
    // `title`, `author` and `authorList` are all derived from the OPF, so they
    // are varied through the metadata rather than by mutating the ref; the
    // remaining two are set directly, since no fixture varies them alone.
    test(
        'TC-REF-3 [Equivalence partitioning]: a differing title breaks '
        'equality', () async {
      final EpubBookRef first =
          await const EpubReader().openBook(seedArchive());
      final EpubBookRef second =
          await const EpubReader().openBook(seedArchive());
      second.title = 'NGE-SEED Other';

      expect(first, isNot(equals(second)));
    });

    test(
        'TC-REF-3 [Equivalence partitioning]: a differing author breaks '
        'equality', () async {
      final EpubBookRef first =
          await const EpubReader().openBook(seedArchive());
      final EpubBookRef second =
          await const EpubReader().openBook(seedArchive());
      second.author = 'NGE-SEED Other';

      expect(first, isNot(equals(second)));
    });

    test(
        'TC-REF-3 [Equivalence partitioning]: a differing authorList breaks '
        'equality', () async {
      final EpubBookRef first =
          await const EpubReader().openBook(seedArchive());
      final EpubBookRef second =
          await const EpubReader().openBook(seedArchive());
      second.authorList = <String?>['NGE-SEED Author One'];

      expect(first, isNot(equals(second)));
      expect(first.hashCode, isNot(equals(second.hashCode)));
    });

    test(
        'TC-REF-3 [Equivalence partitioning]: a differing schema breaks '
        'equality', () async {
      final EpubBookRef first =
          await const EpubReader().openBook(seedArchive());
      final EpubBookRef second =
          await const EpubReader().openBook(seedArchive());
      second.schema!.contentDirectoryPath = 'NGE-SEED-OTHER';

      expect(first, isNot(equals(second)));
    });

    test(
        'TC-REF-3 [Equivalence partitioning]: a differing content breaks '
        'equality', () async {
      final EpubBookRef first =
          await const EpubReader().openBook(seedArchive());
      final EpubBookRef second =
          await const EpubReader().openBook(seedArchive());
      second.content!.html!.remove('chapter1.xhtml');

      expect(first, isNot(equals(second)));
    });

    // TC-REF-4 [Error guessing]: `is!`-guarded, so an unrelated operand is
    // rejected rather than throwing — the trait the OPF and navigation
    // schema classes had to be fixed to match (TC-OPF-1, TC-NSC-1).
    test('TC-REF-4 [Error guessing]: an unrelated operand is not equal',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());

      expect(bookRef == unrelatedOperand, isFalse);
      expect(bookRef == nullOperand, isFalse);
    });

    // TC-REF-5 [Scenario/use-case]: the three delegating methods on the ref —
    // the app's entry into chapters and cover art. `readCover` decodes,
    // `readCoverBytes` does not.
    test(
        'TC-REF-5 [Scenario]: getChapters, readCover and readCoverBytes '
        'delegate', () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(
            coverMeta: '<meta name="cover" content="cover"/>',
          ),
          'OEBPS/toc.ncx': _ncx(),
          'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
          'OEBPS/style.css': 'body { color: #000; }',
        },
        binaryEntries: <String, List<int>>{
          'OEBPS/cover.png': seedPngBytes(),
          'OEBPS/body.ttf': <int>[0, 1, 0, 0],
        },
      );
      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);

      final List<EpubChapterRef> chapters = await bookRef.getChapters();
      expect(chapters, hasLength(1));
      expect(chapters.single.title, 'NGE-SEED Chapter One');

      final Image? cover = await bookRef.readCover();
      expect(cover, isNotNull);
      expect(cover!.width, 2);
      expect(cover.height, 2);

      final Uint8List? coverBytes = await bookRef.readCoverBytes();
      expect(coverBytes, equals(seedPngBytes()));
    });

    // TC-REF-6 [Boundary value]: a book with no cover returns null from both
    // cover methods rather than throwing. The manifest here carries no image
    // AND no item id of `cover` / `cover-image`, because `BookCoverReader`
    // treats those ids as a cover by convention even with no
    // `<meta name="cover">` — which is why `seedArchive`, whose PNG is
    // declared `id="cover"`, does NOT reach this branch.
    test(
        'TC-REF-6 [Boundary]: a coverless book yields null from both cover '
        'methods', () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(
            manifestItems: '<item id="ncx" href="toc.ncx" '
                'media-type="application/x-dtbncx+xml"/>'
                '<item id="ch1" href="chapter1.xhtml" '
                'media-type="application/xhtml+xml"/>',
          ),
          'OEBPS/toc.ncx': _ncx(),
          'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
        },
      );
      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);

      expect(await bookRef.readCover(), isNull);
      expect(await bookRef.readCoverBytes(), isNull);
    });
  });

  group('EpubContentRef', () {
    // TC-REF-7 [Scenario/use-case]: the constructor initialises five empty
    // maps, and `parseContentMap` sorts every manifest item into them.
    test('TC-REF-7 [Scenario]: content is bucketed into the five maps',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubContentRef content = bookRef.content!;

      expect(content.html!.keys, <String>['chapter1.xhtml']);
      expect(content.css!.keys, <String>['style.css']);
      expect(content.images!.keys, <String>['cover.png']);
      expect(content.fonts!.keys, <String>['body.ttf']);
      expect(content.allFiles, hasLength(5));
      expect(content.allFiles!.keys, contains('toc.ncx'));

      // A bare `EpubContentRef()` starts with all five buckets empty.
      final EpubContentRef bare = EpubContentRef();
      expect(bare.html, isEmpty);
      expect(bare.css, isEmpty);
      expect(bare.images, isEmpty);
      expect(bare.fonts, isEmpty);
      expect(bare.allFiles, isEmpty);
    });

    // TC-REF-8 [Scenario/use-case]: two opens produce equal content refs.
    test('TC-REF-8 [Scenario]: content refs from two opens are equal',
        () async {
      final Uint8List bytes = seedArchive();
      final EpubContentRef first =
          (await const EpubReader().openBook(bytes)).content!;
      final EpubContentRef second =
          (await const EpubReader().openBook(bytes)).content!;

      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
      expect(EpubContentRef(), equals(EpubContentRef()));
    });

    // TC-REF-9 [Equivalence partitioning]: each of the five maps decides
    // equality on its own.
    for (final String bucket in <String>[
      'html',
      'css',
      'images',
      'fonts',
      'allFiles',
    ]) {
      test(
          'TC-REF-9 [Equivalence partitioning]: a changed $bucket breaks '
          'equality', () async {
        final Uint8List bytes = seedArchive();
        final EpubContentRef first =
            (await const EpubReader().openBook(bytes)).content!;
        final EpubContentRef second =
            (await const EpubReader().openBook(bytes)).content!;

        switch (bucket) {
          case 'html':
            second.html!.clear();
          case 'css':
            second.css!.clear();
          case 'images':
            second.images!.clear();
          case 'fonts':
            second.fonts!.clear();
          case 'allFiles':
            second.allFiles!.clear();
        }

        expect(first, isNot(equals(second)));
        expect(first.hashCode, isNot(equals(second.hashCode)));
      });
    }

    // TC-REF-10 [Error guessing]: `is!`-guarded.
    test('TC-REF-10 [Error guessing]: an unrelated operand is not equal', () {
      expect(EpubContentRef() == unrelatedOperand, isFalse);
      expect(EpubContentRef() == nullOperand, isFalse);
    });
  });

  group('EpubContentFileRef', () {
    // TC-REF-11 [Scenario/use-case]: the base resolves an archive entry by
    // joining the content directory to the manifest href, then reads it both
    // as bytes and as text.
    test(
        'TC-REF-11 [Scenario]: a content file ref resolves and reads its '
        'entry', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubTextContentFileRef chapter =
          bookRef.content!.html!['chapter1.xhtml']!;

      expect(chapter.fileName, 'chapter1.xhtml');
      expect(chapter.contentMimeType, 'application/xhtml+xml');
      expect(chapter.contentType, EpubContentType.xhtml11);
      expect(chapter.epubBookRef, same(bookRef));

      final ArchiveFile entry = chapter.getContentFileEntry();
      expect(entry.name, 'OEBPS/chapter1.xhtml');

      expect(chapter.getContentStream(), equals(entry.content));
      expect(
        await chapter.readContentAsText(),
        contains('NGE-SEED-CH1'),
      );
      expect(
        await chapter.readContentAsBytes(),
        equals(Uint8List.fromList(entry.content)),
      );
      expect(
        chapter.openContentStream(entry),
        equals(entry.content),
      );
    });

    // TC-REF-12 [Error guessing]: a manifest href with no matching archive
    // entry is rejected as a typed `EpubMissingArchiveEntryException`, with
    // the archive path in the message. The ref's `fileName` is reassigned
    // because a manifest the reader accepted is by construction resolvable —
    // this is the state a hand-edited EPUB reaches.
    test('TC-REF-12 [Error guessing]: an unresolvable file name throws',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubTextContentFileRef chapter =
          bookRef.content!.html!['chapter1.xhtml']!;
      chapter.fileName = 'NGE-SEED-missing.xhtml';

      expect(
        chapter.getContentFileEntry,
        throwsA(
          isA<EpubMissingArchiveEntryException>().having(
            (EpubMissingArchiveEntryException e) => e.message,
            'message',
            contains('OEBPS/NGE-SEED-missing.xhtml not found in archive'),
          ),
        ),
      );
      expect(chapter.getContentStream,
          throwsA(isA<EpubMissingArchiveEntryException>()));
      expect(chapter.readContentAsText,
          throwsA(isA<EpubMissingArchiveEntryException>()));
      expect(chapter.readContentAsBytes,
          throwsA(isA<EpubMissingArchiveEntryException>()));
    });

    // TC-REF-13 [Scenario/use-case]: `==` compares the three declared fields
    // and ignores the book ref, so the same file opened twice from two
    // separate archives compares equal.
    test(
        'TC-REF-13 [Scenario]: refs to the same file from two opens are '
        'equal', () async {
      final Uint8List bytes = seedArchive();
      final EpubTextContentFileRef first =
          (await const EpubReader().openBook(bytes))
              .content!
              .html!['chapter1.xhtml']!;
      final EpubTextContentFileRef second =
          (await const EpubReader().openBook(bytes))
              .content!
              .html!['chapter1.xhtml']!;

      expect(first.epubBookRef, isNot(same(second.epubBookRef)));
      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
    });

    // TC-REF-14 [Equivalence partitioning]: each of the three compared fields
    // decides once.
    for (final String field in <String>[
      'fileName',
      'contentMimeType',
      'contentType',
    ]) {
      test(
          'TC-REF-14 [Equivalence partitioning]: a differing $field breaks '
          'equality', () async {
        final Uint8List bytes = seedArchive();
        final EpubTextContentFileRef first =
            (await const EpubReader().openBook(bytes))
                .content!
                .html!['chapter1.xhtml']!;
        final EpubTextContentFileRef second =
            (await const EpubReader().openBook(bytes))
                .content!
                .html!['chapter1.xhtml']!;

        switch (field) {
          case 'fileName':
            second.fileName = 'NGE-SEED-other.xhtml';
          case 'contentMimeType':
            second.contentMimeType = 'text/html';
          case 'contentType':
            second.contentType = EpubContentType.xml;
        }

        expect(first, isNot(equals(second)));
        expect(first.hashCode, isNot(equals(second.hashCode)));
      });
    }

    // TC-REF-15 [Error guessing]: the base uses `is!` and does NOT narrow to
    // the runtime subclass, so a text ref and a byte ref that agree on all
    // three fields compare EQUAL in both directions. Neither subclass
    // overrides `==`, which is what makes this differ from the loaded
    // entities (TC-ENT-5).
    test(
        'TC-REF-15 [Error guessing]: the base comparison ignores the '
        'subclass', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubTextContentFileRef text =
          bookRef.content!.html!['chapter1.xhtml']!;
      final EpubByteContentFileRef bytes =
          bookRef.content!.images!['cover.png']!;

      expect(text, isNot(equals(bytes)));

      bytes
        ..fileName = text.fileName
        ..contentMimeType = text.contentMimeType
        ..contentType = text.contentType;
      expect(text, equals(bytes));
      expect(bytes, equals(text));

      expect(text == unrelatedOperand, isFalse);
      expect(text == nullOperand, isFalse);
    });

    // TC-REF-16 [Scenario/use-case]: the two subclass convenience methods.
    // `EpubTextContentFileRef.readContentAsync` and
    // `EpubByteContentFileRef.readContent` are thin aliases, and the app calls
    // them rather than the base methods.
    test(
        'TC-REF-16 [Scenario]: the subclass read aliases match the base '
        'methods', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubTextContentFileRef text =
          bookRef.content!.html!['chapter1.xhtml']!;
      final EpubByteContentFileRef image =
          bookRef.content!.images!['cover.png']!;

      expect(
        await text.readContentAsync(),
        equals(await text.readContentAsText()),
      );
      expect(await text.readContentAsync(), contains('NGE-SEED-CH1'));

      expect(
        await image.readContent(),
        equals(await image.readContentAsBytes()),
      );
      expect(await image.readContent(), equals(seedPngBytes()));
    });

    // TC-REF-17 [Boundary value]: a zero-byte archive entry reads back as an
    // empty stream rather than as an error — the empty-file boundary of
    // `openContentStream`.
    test(
        'TC-REF-17 [Boundary]: an empty content file reads as an empty '
        'stream', () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(
            manifestItems: '<item id="ncx" href="toc.ncx" '
                'media-type="application/x-dtbncx+xml"/>'
                '<item id="ch1" href="chapter1.xhtml" '
                'media-type="application/xhtml+xml"/>'
                '<item id="css" href="style.css" media-type="text/css"/>',
          ),
          'OEBPS/toc.ncx': _ncx(),
          'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
          'OEBPS/style.css': '',
        },
      );
      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);
      final EpubTextContentFileRef css = bookRef.content!.css!['style.css']!;

      expect(css.getContentStream(), isEmpty);
      expect(await css.readContentAsText(), isEmpty);
      expect(await css.readContentAsBytes(), isEmpty);
    });

    // TC-REF-25 [Error guessing]: `openContentStream`'s null-content guard.
    // No archive this package can DECODE reaches it — `ArchiveFile.content`
    // repopulates itself from `_rawContent` on demand, so even a `clear()`ed
    // entry reads back non-null. The one way in is an entry carrying neither
    // content nor raw content, which is why the `ArchiveFile` is built here
    // rather than taken from the fixture; the ref it is handed to still comes
    // from `EpubReader.openBook`. If that guard is ever deleted as dead code,
    // this test goes with it.
    test(
        'TC-REF-25 [Error guessing]: an entry with no content at all is '
        'rejected', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubTextContentFileRef chapter =
          bookRef.content!.html!['chapter1.xhtml']!;

      final ArchiveFile empty = ArchiveFile('OEBPS/chapter1.xhtml', 0, null);
      expect(empty.content, isNull);

      expect(
        () => chapter.openContentStream(empty),
        throwsA(
          isA<EpubMissingArchiveEntryException>().having(
            (EpubMissingArchiveEntryException e) => e.message,
            'message',
            contains('content file "chapter1.xhtml" specified in manifest is '
                'not found'),
          ),
        ),
      );
    });
  });

  group('EpubChapterRef', () {
    // TC-REF-18 [Scenario/use-case]: a single-file chapter carries its text
    // ref, its title and its content file name, and reads its html directly.
    test('TC-REF-18 [Scenario]: a single-file chapter reads its html',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubChapterRef chapter = (await bookRef.getChapters()).single;

      expect(chapter.title, 'NGE-SEED Chapter One');
      expect(chapter.contentFileName, 'chapter1.xhtml');
      expect(chapter.anchor, isNull);
      expect(chapter.subChapters, isEmpty);
      expect(chapter.otherContentFileNames, isEmpty);
      expect(chapter.otherTextContentFileRefs, isEmpty);
      expect(chapter.epubTextContentFileRef, isNotNull);
      expect(await chapter.readHtmlContent(), contains('NGE-SEED-CH1'));
    });

    // TC-REF-19 [Scenario/use-case]: a chapter split across files concatenates
    // every part, in the order the reader collected them. This is the only
    // branch of `readHtmlContent` that uses `Future.wait`, and the `_split_`
    // href marker is the only thing that reaches it.
    test('TC-REF-19 [Scenario]: a split chapter concatenates all its parts',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedSplitChapterArchive());
      final EpubChapterRef chapter = (await bookRef.getChapters()).single;

      expect(chapter.contentFileName, 'part_split_000.xhtml');
      expect(
        chapter.otherContentFileNames,
        <String>['part_split_001.xhtml'],
      );
      expect(chapter.otherTextContentFileRefs, hasLength(1));
      expect(
        await chapter.readHtmlContent(),
        '<p>NGE-SEED-PART-A</p><p>NGE-SEED-PART-B</p>',
      );
    });

    // TC-REF-20 [Scenario/use-case]: an anchored navPoint splits into file
    // name and anchor, and nested navPoints become subchapters.
    test('TC-REF-20 [Scenario]: anchors and subchapters are carried through',
        () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(),
          'OEBPS/toc.ncx': _ncx(
            navPoints: '<navPoint id="np-1" playOrder="1">'
                '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
                '<content src="chapter1.xhtml"/>'
                '<navPoint id="np-1-1" playOrder="2">'
                '<navLabel><text>NGE-SEED Section One</text></navLabel>'
                '<content src="chapter1.xhtml#NGE-SEED-s1"/>'
                '</navPoint>'
                '</navPoint>',
          ),
          'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
          'OEBPS/style.css': 'body { color: #000; }',
        },
        binaryEntries: <String, List<int>>{
          'OEBPS/cover.png': seedPngBytes(),
          'OEBPS/body.ttf': <int>[0, 1, 0, 0],
        },
      );
      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);
      final EpubChapterRef chapter = (await bookRef.getChapters()).single;

      expect(chapter.subChapters, hasLength(1));
      final EpubChapterRef sub = chapter.subChapters!.single;
      expect(sub.title, 'NGE-SEED Section One');
      expect(sub.contentFileName, 'chapter1.xhtml');
      expect(sub.anchor, 'NGE-SEED-s1');
      expect(chapter.toString(),
          'Title: NGE-SEED Chapter One, Subchapter count: 1');
    });

    // TC-REF-21 [Error guessing]: the regression guard for the identity
    // comparison this class carried alongside `EpubChapter` (TC-ENT-22). The
    // two split-chapter lists — `otherContentFileNames` and
    // `otherTextContentFileRefs` — were compared with `==` on the list
    // OBJECTS while `subChapters` went through `listsEqual`, and every ref
    // gets its own fresh list from the field initialiser, so two refs over one
    // archive were never equal and never shared a `hashCode`. Both are now
    // compared and hashed by element.
    test(
        'TC-REF-21 [Error guessing]: chapter refs from two opens of one '
        'archive are equal', () async {
      final Uint8List bytes = seedArchive();
      final EpubChapterRef first =
          (await (await const EpubReader().openBook(bytes)).getChapters())
              .single;
      final EpubChapterRef second =
          (await (await const EpubReader().openBook(bytes)).getChapters())
              .single;

      expect(first.title, equals(second.title));
      expect(first.otherContentFileNames, equals(second.otherContentFileNames));
      expect(
        identical(first.otherContentFileNames, second.otherContentFileNames),
        isFalse,
      );
      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));

      // The split-chapter list still decides equality when it differs.
      second.otherContentFileNames = <String>['NGE-SEED-part2.xhtml'];
      expect(first, isNot(equals(second)));
    });

    // TC-REF-22 [Equivalence partitioning]: each remaining field decides
    // equality once.
    for (final String field in <String>[
      'title',
      'contentFileName',
      'anchor',
      'epubTextContentFileRef',
      'subChapters',
    ]) {
      test(
          'TC-REF-22 [Equivalence partitioning]: a differing $field breaks '
          'equality', () async {
        final Uint8List bytes = seedArchive();
        final EpubBookRef bookRef = await const EpubReader().openBook(bytes);
        final EpubChapterRef first = (await bookRef.getChapters()).single;
        final EpubChapterRef second =
            (await (await const EpubReader().openBook(bytes)).getChapters())
                .single;

        switch (field) {
          case 'title':
            second.title = 'NGE-SEED Other';
          case 'contentFileName':
            second.contentFileName = 'NGE-SEED-other.xhtml';
          case 'anchor':
            second.anchor = 'NGE-SEED-anchor';
          case 'epubTextContentFileRef':
            second.epubTextContentFileRef = null;
          case 'subChapters':
            second.subChapters = null;
        }

        expect(first, isNot(equals(second)));
      });
    }

    // TC-REF-23 [Error guessing]: `is!`-guarded, so an unrelated operand is
    // rejected without throwing.
    test('TC-REF-23 [Error guessing]: an unrelated operand is not equal',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubChapterRef chapter = (await bookRef.getChapters()).single;

      expect(chapter == unrelatedOperand, isFalse);
      expect(chapter == nullOperand, isFalse);
    });

    // TC-REF-24 [Boundary value]: a book whose NCX has no navPoints yields no
    // chapter refs at all — the empty boundary of `getChapters`.
    test('TC-REF-24 [Boundary]: a navMap with no points yields no chapters',
        () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(
            manifestItems: '<item id="ncx" href="toc.ncx" '
                'media-type="application/x-dtbncx+xml"/>'
                '<item id="ch1" href="chapter1.xhtml" '
                'media-type="application/xhtml+xml"/>',
          ),
          'OEBPS/toc.ncx': '<?xml version="1.0" encoding="UTF-8"?>'
              '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" '
              'version="2005-1">'
              '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-REF"/>'
              '</head>'
              '<docTitle><text>NGE-SEED Ref Book</text></docTitle>'
              '<navMap/>'
              '</ncx>',
          'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
        },
      );
      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);

      expect(await bookRef.getChapters(), isEmpty);
    });

    // TC-REF-25 [Error guessing]: the regression guard for the `?? [0]`
    // fallback in `hashCode`. TC-REF-22 already shows a differing
    // subChapters breaks equality; nothing previously checked that two
    // DIFFERING non-null subChapters lists also hash differently.
    test(
        'TC-REF-25 [Error guessing]: differing non-null subChapters yields a '
        'differing hashCode', () async {
      Future<EpubChapterRef> chapterWithSubLabel(String label) async {
        final Uint8List bytes = buildEpubArchive(
          opfPath: 'OEBPS/content.opf',
          textEntries: <String, String>{
            'OEBPS/content.opf': _opf(),
            'OEBPS/toc.ncx': _ncx(
              navPoints: '<navPoint id="np-1" playOrder="1">'
                  '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
                  '<content src="chapter1.xhtml"/>'
                  '<navPoint id="np-1-1" playOrder="2">'
                  '<navLabel><text>$label</text></navLabel>'
                  '<content src="chapter1.xhtml#$label"/>'
                  '</navPoint>'
                  '</navPoint>',
            ),
            'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
            'OEBPS/style.css': 'body { color: #000; }',
          },
          binaryEntries: <String, List<int>>{
            'OEBPS/cover.png': seedPngBytes(),
            'OEBPS/body.ttf': <int>[0, 1, 0, 0],
          },
        );
        final EpubBookRef bookRef = await const EpubReader().openBook(bytes);
        return (await bookRef.getChapters()).single;
      }

      final EpubChapterRef a = await chapterWithSubLabel('NGE-SEED Sub One');
      final EpubChapterRef b = await chapterWithSubLabel('NGE-SEED Sub Two');

      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    // TC-REF-26 [Boundary value]: the null half of the same fallback. A
    // chapter whose `subChapters` is nulled still hashes, and differently
    // from its twin that keeps the (empty) list — the two are unequal, so a
    // `?? []` fallback, which hashes like the empty list, would collide.
    test(
        'TC-REF-26 [Boundary]: null subChapters hashes, and differently from '
        'an empty list', () async {
      Future<EpubChapterRef> chapter() async =>
          (await (await const EpubReader().openBook(seedArchive()))
                  .getChapters())
              .single;
      final EpubChapterRef withList = await chapter();
      final EpubChapterRef withNull = await chapter()
        ..subChapters = null;

      expect(withList.subChapters, isEmpty);
      expect(withNull.hashCode, isA<int>());
      expect(withNull.hashCode, isNot(equals(withList.hashCode)));
    });
  });
}
