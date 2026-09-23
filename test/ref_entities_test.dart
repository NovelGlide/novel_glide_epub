// The lazy, archive-backed `*Ref` entities — `EpubBookRef`, `EpubContentRef`,
// `EpubContentFileRef` and its two subclasses, and `EpubChapterRef`.
//
// Unlike the plain entities, these hold a live `Archive` handle and read from
// it on demand, so every fixture here starts from the public entry point
// `EpubReader.openBook`: the ref under test is the shape the reader actually
// produces. Where a test needs a ref the reader cannot produce from a real
// file — one that differs from its twin in a single field, or points at an
// entry the archive lacks — it rebuilds a reader-produced ref through the
// public constructor, over the same archive, changing only that field.
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

/// The single chapter ref of [bytes], read through `EpubReader.openBook`.
Future<EpubChapterRef> openSingleChapter(Uint8List bytes) async =>
    (await (await const EpubReader().openBook(bytes)).getChapters()).single;

/// [ref] rebuilt over the same archive, with any field given here replaced.
EpubBookRef copyBookRef(
  EpubBookRef ref, {
  String? title,
  List<String>? authorList,
  EpubSchema? schema,
  EpubContentRef? content,
}) =>
    EpubBookRef(
      epubArchive: ref.epubArchive(),
      title: title ?? ref.title,
      authorList: authorList ?? ref.authorList,
      schema: schema ?? ref.schema,
      content: content ?? ref.content,
    );

/// [ref] rebuilt with any field given here replaced. [anchor] can only be
/// replaced by a non-null value, which is all a test here needs.
EpubChapterRef copyChapterRef(
  EpubChapterRef ref, {
  EpubTextContentFileRef? epubTextContentFileRef,
  String? title,
  String? contentFileName,
  String? anchor,
  List<EpubChapterRef>? subChapters,
  List<EpubTextContentFileRef>? otherTextContentFileRefs,
  List<String>? otherContentFileNames,
}) =>
    EpubChapterRef(
      epubTextContentFileRef:
          epubTextContentFileRef ?? ref.epubTextContentFileRef,
      title: title ?? ref.title,
      contentFileName: contentFileName ?? ref.contentFileName,
      anchor: anchor ?? ref.anchor,
      subChapters: subChapters ?? ref.subChapters,
      otherTextContentFileRefs:
          otherTextContentFileRefs ?? ref.otherTextContentFileRefs,
      otherContentFileNames: otherContentFileNames ?? ref.otherContentFileNames,
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
      expect(bookRef.schema.contentDirectoryPath, 'OEBPS');
      expect(bookRef.epubArchive(), isA<Archive>());
      expect(
        bookRef.epubArchive().files.map((ArchiveFile f) => f.name),
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
    // The differing twin is the opened ref rebuilt with that one field
    // replaced, since no single fixture change varies one field alone.
    for (final String field in <String>[
      'title',
      'authorList',
      'schema',
      'content',
    ]) {
      test(
          'TC-REF-3 [Equivalence partitioning]: a differing $field breaks '
          'equality', () async {
        final EpubBookRef first =
            await const EpubReader().openBook(seedArchive());
        final EpubBookRef second = switch (field) {
          'title' => copyBookRef(first, title: 'NGE-SEED Other'),
          'authorList' =>
            copyBookRef(first, authorList: <String>['NGE-SEED Author One']),
          'schema' => copyBookRef(
              first,
              schema: EpubSchema(
                package: first.schema.package,
                navigation: first.schema.navigation,
                contentDirectoryPath: 'NGE-SEED-OTHER',
              ),
            ),
          _ => copyBookRef(
              first,
              content: EpubContentRef(
                css: first.content.css,
                images: first.content.images,
                fonts: first.content.fonts,
                allFiles: first.content.allFiles,
              ),
            ),
        };

        expect(first, isNot(equals(second)));
        expect(first.hashCode, isNot(equals(second.hashCode)));
        // The twin is rebuilt faithfully: with no field replaced it is equal.
        expect(copyBookRef(first), equals(first));
      });
    }

    // TC-REF-4 [Error guessing]: `is!`-guarded, so an unrelated operand is
    // rejected rather than throwing — the trait the OPF and navigation
    // schema classes share (TC-OPF-1, TC-NSC-1).
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
    // TC-REF-7 [Scenario/use-case]: the constructor defaults to five empty
    // maps, and `parseContentMap` sorts every manifest item into them.
    test('TC-REF-7 [Scenario]: content is bucketed into the five maps',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubContentRef content = bookRef.content;

      expect(content.html.keys, <String>['chapter1.xhtml']);
      expect(content.css.keys, <String>['style.css']);
      expect(content.images.keys, <String>['cover.png']);
      expect(content.fonts.keys, <String>['body.ttf']);
      expect(content.allFiles, hasLength(5));
      expect(content.allFiles.keys, contains('toc.ncx'));

      // A bare `EpubContentRef()` starts with all five buckets empty.
      const EpubContentRef bare = EpubContentRef();
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
          (await const EpubReader().openBook(bytes)).content;
      final EpubContentRef second =
          (await const EpubReader().openBook(bytes)).content;

      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
      expect(const EpubContentRef(), equals(const EpubContentRef()));
    });

    // TC-REF-9 [Equivalence partitioning]: each of the five maps decides
    // equality on its own. The twin is the opened content with that one map
    // left at its empty default.
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
        final EpubContentRef first =
            (await const EpubReader().openBook(seedArchive())).content;
        final EpubContentRef second = switch (bucket) {
          'html' => EpubContentRef(
              css: first.css,
              images: first.images,
              fonts: first.fonts,
              allFiles: first.allFiles,
            ),
          'css' => EpubContentRef(
              html: first.html,
              images: first.images,
              fonts: first.fonts,
              allFiles: first.allFiles,
            ),
          'images' => EpubContentRef(
              html: first.html,
              css: first.css,
              fonts: first.fonts,
              allFiles: first.allFiles,
            ),
          'fonts' => EpubContentRef(
              html: first.html,
              css: first.css,
              images: first.images,
              allFiles: first.allFiles,
            ),
          _ => EpubContentRef(
              html: first.html,
              css: first.css,
              images: first.images,
              fonts: first.fonts,
            ),
        };

        expect(first, isNot(equals(second)));
        expect(first.hashCode, isNot(equals(second.hashCode)));
      });
    }

    // TC-REF-10 [Error guessing]: `is!`-guarded.
    test('TC-REF-10 [Error guessing]: an unrelated operand is not equal', () {
      expect(const EpubContentRef() == unrelatedOperand, isFalse);
      expect(const EpubContentRef() == nullOperand, isFalse);
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
          bookRef.content.html['chapter1.xhtml']!;

      expect(chapter.fileName, 'chapter1.xhtml');
      expect(chapter.contentMimeType, 'application/xhtml+xml');
      expect(chapter.contentType, EpubContentType.xhtml11);

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
    // the archive path in the message. A manifest the reader accepted is by
    // construction resolvable, so the ref is rebuilt over the opened archive
    // with a missing name — the state a hand-edited EPUB reaches.
    test('TC-REF-12 [Error guessing]: an unresolvable file name throws',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubTextContentFileRef chapter = EpubTextContentFileRef(
        epubArchive: bookRef.epubArchive(),
        contentDirectoryPath: bookRef.schema.contentDirectoryPath,
        fileName: 'NGE-SEED-missing.xhtml',
        contentType: EpubContentType.xhtml11,
        contentMimeType: 'application/xhtml+xml',
      );

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
    // and ignores the archive, so the same file opened twice from two
    // separately decoded archives compares equal.
    test(
        'TC-REF-13 [Scenario]: refs to the same file from two opens are '
        'equal', () async {
      final Uint8List bytes = seedArchive();
      final EpubBookRef firstBook = await const EpubReader().openBook(bytes);
      final EpubBookRef secondBook = await const EpubReader().openBook(bytes);
      final EpubTextContentFileRef first =
          firstBook.content.html['chapter1.xhtml']!;
      final EpubTextContentFileRef second =
          secondBook.content.html['chapter1.xhtml']!;

      expect(firstBook.epubArchive(), isNot(same(secondBook.epubArchive())));
      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));
    });

    // TC-REF-14 [Equivalence partitioning]: each of the three compared fields
    // decides once. The twin is the opened ref rebuilt over the same archive
    // with that one field replaced.
    for (final String field in <String>[
      'fileName',
      'contentMimeType',
      'contentType',
    ]) {
      test(
          'TC-REF-14 [Equivalence partitioning]: a differing $field breaks '
          'equality', () async {
        final EpubBookRef bookRef =
            await const EpubReader().openBook(seedArchive());
        final EpubTextContentFileRef first =
            bookRef.content.html['chapter1.xhtml']!;
        final EpubTextContentFileRef second = EpubTextContentFileRef(
          epubArchive: bookRef.epubArchive(),
          contentDirectoryPath: bookRef.schema.contentDirectoryPath,
          fileName:
              field == 'fileName' ? 'NGE-SEED-other.xhtml' : first.fileName,
          contentMimeType:
              field == 'contentMimeType' ? 'text/html' : first.contentMimeType,
          contentType:
              field == 'contentType' ? EpubContentType.xml : first.contentType,
        );

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
          bookRef.content.html['chapter1.xhtml']!;
      final EpubByteContentFileRef image = bookRef.content.images['cover.png']!;

      expect(text, isNot(equals(image)));

      final EpubByteContentFileRef bytes = EpubByteContentFileRef(
        epubArchive: bookRef.epubArchive(),
        contentDirectoryPath: bookRef.schema.contentDirectoryPath,
        fileName: text.fileName,
        contentMimeType: text.contentMimeType,
        contentType: text.contentType,
      );
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
          bookRef.content.html['chapter1.xhtml']!;
      final EpubByteContentFileRef image = bookRef.content.images['cover.png']!;

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
      final EpubTextContentFileRef css = bookRef.content.css['style.css']!;

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
          bookRef.content.html['chapter1.xhtml']!;

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
      expect(
        chapter.epubTextContentFileRef,
        same(bookRef.content.html['chapter1.xhtml']),
      );
      expect(await chapter.readHtmlContent(), contains('NGE-SEED-CH1'));
    });

    // TC-REF-19 [Scenario/use-case]: a chapter split across files concatenates
    // every part, in the order the reader collected them. The `_split_` href
    // marker is the only thing that gives a chapter from a real file more
    // than one part.
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
      final EpubChapterRef sub = chapter.subChapters.single;
      expect(sub.title, 'NGE-SEED Section One');
      expect(sub.contentFileName, 'chapter1.xhtml');
      expect(sub.anchor, 'NGE-SEED-s1');
      expect(chapter.toString(),
          'Title: NGE-SEED Chapter One, Subchapter count: 1');
      expect(
          sub.toString(), 'Title: NGE-SEED Section One, Subchapter count: 0');
    });

    // TC-REF-21 [Error guessing]: the two split-chapter lists —
    // `otherContentFileNames` and `otherTextContentFileRefs` — are compared
    // with `listsEqual` and hashed by element, like `subChapters`. The reader
    // hands every ref lists of its own, so a comparison by list identity
    // would make two refs over one archive unequal and hash them apart.
    test(
        'TC-REF-21 [Error guessing]: chapter refs from two opens of one '
        'archive are equal', () async {
      final Uint8List bytes = seedArchive();
      final EpubChapterRef first = await openSingleChapter(bytes);
      final EpubChapterRef second = await openSingleChapter(bytes);

      expect(first.title, equals(second.title));
      expect(first.otherContentFileNames, equals(second.otherContentFileNames));
      expect(
        identical(first.otherContentFileNames, second.otherContentFileNames),
        isFalse,
      );
      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));

      // The split-chapter list still decides equality, and the hash, when it
      // differs.
      final EpubChapterRef renamed = copyChapterRef(
        second,
        otherContentFileNames: <String>['NGE-SEED-part2.xhtml'],
      );
      expect(first, isNot(equals(renamed)));
      expect(first.hashCode, isNot(equals(renamed.hashCode)));
    });

    // TC-REF-22 [Equivalence partitioning]: each remaining field decides
    // equality once. Every row differs from the opened ref in that field
    // alone, so each clause of the `&&` chain is the one that decides.
    for (final String field in <String>[
      'title',
      'contentFileName',
      'anchor',
      'epubTextContentFileRef',
      'otherTextContentFileRefs',
      'subChapters',
    ]) {
      test(
          'TC-REF-22 [Equivalence partitioning]: a differing $field breaks '
          'equality', () async {
        final EpubBookRef bookRef =
            await const EpubReader().openBook(seedArchive());
        final EpubChapterRef first = (await bookRef.getChapters()).single;
        final EpubTextContentFileRef css = bookRef.content.css['style.css']!;
        final EpubChapterRef second = switch (field) {
          'title' => copyChapterRef(first, title: 'NGE-SEED Other'),
          'contentFileName' =>
            copyChapterRef(first, contentFileName: 'NGE-SEED-other.xhtml'),
          'anchor' => copyChapterRef(first, anchor: 'NGE-SEED-anchor'),
          'epubTextContentFileRef' =>
            copyChapterRef(first, epubTextContentFileRef: css),
          'otherTextContentFileRefs' => copyChapterRef(
              first,
              otherTextContentFileRefs: <EpubTextContentFileRef>[css],
            ),
          _ => copyChapterRef(
              first,
              subChapters: <EpubChapterRef>[copyChapterRef(first)],
            ),
        };

        expect(first, isNot(equals(second)));
        expect(second, isNot(equals(first)));
        // The twin is rebuilt faithfully: with no field replaced it is equal.
        expect(copyChapterRef(first), equals(first));
      });
    }

    // TC-REF-23 [Error guessing]: `is!`-guarded, so an unrelated operand is
    // rejected without throwing.
    test('TC-REF-23 [Error guessing]: an unrelated operand is not equal',
        () async {
      final EpubChapterRef chapter = await openSingleChapter(seedArchive());

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

    // TC-REF-25 [Error guessing]: `subChapters` feeds `hashCode` by element.
    // TC-REF-22 shows a differing subChapters breaks equality; this is the
    // half that shows two DIFFERING subchapter lists also hash differently.
    test(
        'TC-REF-25 [Error guessing]: differing subChapters yields a '
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
        return openSingleChapter(bytes);
      }

      final EpubChapterRef a = await chapterWithSubLabel('NGE-SEED Sub One');
      final EpubChapterRef b = await chapterWithSubLabel('NGE-SEED Sub Two');

      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    // TC-REF-27 [Error guessing]: the element-wise comparison and hash of the
    // split-chapter lists, over lists that are NOT empty. TC-REF-21 shows it
    // on the empty lists a single-file chapter carries; here both lists hold
    // a part, so hashing either list as an object, or leaving either out of
    // `hashCode`, would show.
    test(
        'TC-REF-27 [Error guessing]: split chapter refs from two opens are '
        'equal and hash alike', () async {
      final Uint8List bytes = seedSplitChapterArchive();
      final EpubChapterRef first = await openSingleChapter(bytes);
      final EpubChapterRef second = await openSingleChapter(bytes);

      expect(first.otherTextContentFileRefs, hasLength(1));
      expect(
        identical(
            first.otherTextContentFileRefs, second.otherTextContentFileRefs),
        isFalse,
      );
      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));

      // Swapping the one extra part for the chapter's own first part leaves
      // the names alone and changes only the ref list — which still moves
      // the hash.
      final EpubChapterRef otherPart = copyChapterRef(
        second,
        otherTextContentFileRefs: <EpubTextContentFileRef>[
          second.epubTextContentFileRef,
        ],
      );
      expect(first, isNot(equals(otherPart)));
      expect(first.hashCode, isNot(equals(otherPart.hashCode)));
    });

    // TC-REF-28 [Scenario/use-case]: `readHtmlContent` joins the chapter's
    // own file first, then each extra part in list order — not by file name.
    // The reader always lists the parts in name order, so only a ref built
    // with the parts the other way round can tell the two orders apart.
    test('TC-REF-28 [Scenario]: the parts join in list order, own file first',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedSplitChapterArchive());
      final EpubTextContentFileRef partA =
          bookRef.content.html['part_split_000.xhtml']!;
      final EpubTextContentFileRef partB =
          bookRef.content.html['part_split_001.xhtml']!;

      final EpubChapterRef reversed = EpubChapterRef(
        epubTextContentFileRef: partB,
        title: 'NGE-SEED Reversed',
        contentFileName: 'part_split_001.xhtml',
        otherTextContentFileRefs: <EpubTextContentFileRef>[partA],
        otherContentFileNames: <String>['part_split_000.xhtml'],
      );

      expect(
        await reversed.readHtmlContent(),
        '<p>NGE-SEED-PART-B</p><p>NGE-SEED-PART-A</p>',
      );
    });

    // TC-REF-29 [Boundary value]: a chapter ref built from its required
    // fields alone defaults to no anchor, no subchapters and no extra parts —
    // the shape the reader gives a single-file chapter — so it equals and
    // hashes like the reader's own ref, and reads the one file.
    test(
        'TC-REF-29 [Boundary]: a chapter ref built from its required fields '
        'matches the reader\'s single-file chapter', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(seedArchive());
      final EpubChapterRef fromReader = (await bookRef.getChapters()).single;

      final EpubChapterRef bare = EpubChapterRef(
        epubTextContentFileRef: bookRef.content.html['chapter1.xhtml']!,
        title: 'NGE-SEED Chapter One',
        contentFileName: 'chapter1.xhtml',
      );

      expect(bare.anchor, isNull);
      expect(bare.subChapters, isEmpty);
      expect(bare.otherTextContentFileRefs, isEmpty);
      expect(bare.otherContentFileNames, isEmpty);
      expect(bare, equals(fromReader));
      expect(bare.hashCode, equals(fromReader.hashCode));
      expect(await bare.readHtmlContent(), contains('NGE-SEED-CH1'));
      expect(
          bare.toString(), 'Title: NGE-SEED Chapter One, Subchapter count: 0');
    });
  });
}
