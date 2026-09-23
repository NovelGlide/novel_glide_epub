// The loaded-value entities — `EpubBook`, `EpubChapter`, `EpubContent`,
// `EpubContentFile` and its two subclasses, and `EpubSchema`.
//
// These are immutable data holders whose only behaviour is `==`, `hashCode`
// and `toString`, so they are exercised by direct construction; the
// archive-backed half of the package is covered through `EpubReader` in the
// reader suites.
//
// Two contracts shape this file. `EpubChapter` compares and hashes
// `otherContentFileNames` by element, not by list identity (TC-ENT-22), and
// `EpubBook.==` answers false, rather than throwing, when exactly one side
// has a cover (TC-ENT-30). TC-ENT-33 is where element-wise comparison shows
// up on values the reader actually produces.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

/// A 1x1 image whose single pixel is [value] on every channel — two images
/// built with different values differ in `getBytes()`, which is what
/// `EpubBook.==` compares.
Image seedImage(int value) {
  final Image image = Image(width: 1, height: 1);
  image.setPixelRgb(0, 0, value, value, value);
  return image;
}

EpubTextContentFile seedTextFile({
  String fileName = 'NGE-SEED-chapter.xhtml',
  String content = 'NGE-SEED body',
  EpubContentType contentType = EpubContentType.xhtml11,
  String mimeType = 'application/xhtml+xml',
}) =>
    EpubTextContentFile(
      fileName: fileName,
      content: content,
      contentType: contentType,
      contentMimeType: mimeType,
    );

EpubByteContentFile seedByteFile({
  String fileName = 'NGE-SEED-cover.png',
  List<int> content = const <int>[1, 2, 3],
  EpubContentType contentType = EpubContentType.imagePng,
  String mimeType = 'image/png',
}) =>
    EpubByteContentFile(
      fileName: fileName,
      content: content,
      contentType: contentType,
      contentMimeType: mimeType,
    );

/// [otherContentFileNames] is a parameter so a test can vary the
/// split-chapter list, and hand each side of a comparison its own list.
EpubChapter seedChapter({
  String title = 'NGE-SEED Chapter',
  String contentFileName = 'NGE-SEED-chapter.xhtml',
  String? anchor,
  String htmlContent = '<p>NGE-SEED</p>',
  List<EpubChapter> subChapters = const <EpubChapter>[],
  List<String> otherContentFileNames = const <String>[],
}) =>
    EpubChapter(
      title: title,
      contentFileName: contentFileName,
      anchor: anchor,
      htmlContent: htmlContent,
      subChapters: subChapters,
      otherContentFileNames: otherContentFileNames,
    );

/// The smallest package the constructors accept: every list the OPF requires
/// is empty, which is how a real file missing those elements reads.
EpubPackage seedPackage({EpubVersion version = EpubVersion.epub2}) =>
    EpubPackage(
      version: version,
      metadata: const EpubMetadata(
        titles: <String>[],
        identifiers: <EpubMetadataIdentifier>[],
        languages: <String>[],
      ),
      manifest: const EpubManifest(items: <EpubManifestItem>[]),
      spine: const EpubSpine(items: <EpubSpineItemRef>[], ltr: true),
    );

/// The smallest navigation the constructors accept, in the same spirit as
/// [seedPackage].
EpubNavigation seedNavigation({
  List<EpubNavigationDocAuthor> docAuthors = const <EpubNavigationDocAuthor>[],
}) =>
    EpubNavigation(
      head: const EpubNavigationHead(metadata: <EpubNavigationHeadMeta>[]),
      docTitle: const EpubNavigationDocTitle(titles: <String>[]),
      navMap: const EpubNavigationMap(points: <EpubNavigationPoint>[]),
      docAuthors: docAuthors,
    );

EpubSchema seedSchema({
  String contentDirectoryPath = 'OEBPS',
  EpubPackage? package,
  EpubNavigation? navigation,
}) =>
    EpubSchema(
      contentDirectoryPath: contentDirectoryPath,
      package: package ?? seedPackage(),
      navigation: navigation ?? seedNavigation(),
    );

EpubBook seedBook({
  String title = 'NGE-SEED Book',
  List<String> authorList = const <String>['NGE-SEED Author'],
  EpubSchema? schema,
  EpubContent content = const EpubContent(),
  List<EpubChapter>? chapters,
  Image? coverImage,
}) =>
    EpubBook(
      title: title,
      authorList: authorList,
      schema: schema ?? seedSchema(),
      content: content,
      chapters: chapters ?? <EpubChapter>[seedChapter()],
      coverImage: coverImage,
    );

/// The smallest possible concrete `EpubContentFile`.
///
/// Both shipped subclasses override `==` and `hashCode`, so the base
/// implementations are unreachable from anything this package constructs — see
/// TC-ENT-36. They are nonetheless public API: `EpubContentFile` is exported
/// and abstract rather than sealed, and any further subclass inherits them.
/// This class is what lets the base behaviour be pinned at all.
class SeedBareContentFile extends EpubContentFile {
  const SeedBareContentFile({
    super.fileName = 'NGE-SEED-bare',
    super.contentType = EpubContentType.other,
    super.contentMimeType = 'application/octet-stream',
  });
}

/// An operand of an unrelated type, held as `Object` so each comparison below
/// is a real runtime check. Typing it `Object` rather than inlining a literal
/// is what keeps these tests free of an `unrelated_type_equality_checks`
/// suppression, which this package's lint forbids outright.
const Object unrelatedOperand = 'NGE-SEED-not-a-domain-object';

/// A null operand, typed nullable so the analyzer does not fold the comparison
/// away as a statically-known mismatch. Every class under test must answer
/// false here rather than throw.
const Object? nullOperand = null;

/// The same idea as [unrelatedOperand], for the one site that needs a
/// non-String operand.
const Object unrelatedNumber = 42;

void main() {
  group('EpubContentFile (the abstract base, via its subclasses)', () {
    // TC-ENT-1 [Scenario/use-case]: the base `==` compares exactly the three
    // fields it declares, and equal files agree on `hashCode`.
    test('TC-ENT-1 [Scenario]: identical field sets are equal', () {
      final EpubTextContentFile a = seedTextFile();
      final EpubTextContentFile b = seedTextFile();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    // TC-ENT-2 [Equivalence partitioning]: one differing field per run, so
    // every operand of the `&&` chain is the one that decides.
    for (final MapEntry<String, EpubTextContentFile> row
        in <String, EpubTextContentFile>{
      'fileName': seedTextFile(fileName: 'NGE-SEED-other.xhtml'),
      'contentType': seedTextFile(contentType: EpubContentType.xml),
      'contentMimeType': seedTextFile(mimeType: 'application/xml'),
      'content': seedTextFile(content: 'NGE-SEED different body'),
    }.entries) {
      test(
          'TC-ENT-2 [Equivalence partitioning]: a differing ${row.key} '
          'breaks equality', () {
        expect(seedTextFile(), isNot(equals(row.value)));
      });
    }

    // TC-ENT-3 [Error guessing]: the entity classes use `is!`, so an unrelated
    // operand is rejected rather than throwing — the trait the OPF schema
    // classes share (TC-OPF-1).
    test('TC-ENT-3 [Error guessing]: an unrelated operand is not equal', () {
      expect(seedTextFile() == unrelatedOperand, isFalse);
      expect(seedTextFile() == nullOperand, isFalse);
    });

    // TC-ENT-4 [Boundary value]: every string empty is the floor of each
    // field — the reader writes `''` for a required value the file lacks —
    // and it still hashes and compares like any other value.
    test('TC-ENT-4 [Boundary]: two all-empty text files are equal', () {
      const EpubTextContentFile a = EpubTextContentFile(
        fileName: '',
        content: '',
        contentType: EpubContentType.other,
        contentMimeType: '',
      );
      const EpubTextContentFile b = EpubTextContentFile(
        fileName: '',
        content: '',
        contentType: EpubContentType.other,
        contentMimeType: '',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(seedTextFile())));
    });

    // TC-ENT-5 [Scenario/use-case]: both subclasses override `==` and narrow
    // to their own runtime type, so a text file and a byte file are unequal in
    // BOTH directions even when the three base fields match. The base
    // implementation is therefore never what decides between two subclass
    // instances.
    test('TC-ENT-5 [Scenario]: the two subclasses reject each other', () {
      final EpubContentFile text = seedTextFile(
        fileName: 'NGE-SEED-shared',
        contentType: EpubContentType.other,
        mimeType: 'application/octet-stream',
        content: '',
      );
      final EpubContentFile bytes = seedByteFile(
        fileName: 'NGE-SEED-shared',
        contentType: EpubContentType.other,
        mimeType: 'application/octet-stream',
        content: <int>[],
      );

      expect(bytes, isNot(equals(text)));
      expect(text, isNot(equals(bytes)));
      expect(text.fileName, equals(bytes.fileName));
      expect(text.contentType, equals(bytes.contentType));
      expect(text.contentMimeType, equals(bytes.contentMimeType));
    });

    // TC-ENT-36 [Scenario/use-case]: the base's own `==` and `hashCode`, which
    // no instance this package builds can reach — both shipped subclasses
    // override them. Exercised through `SeedBareContentFile` so the inherited
    // behaviour is pinned for any future subclass.
    test(
        'TC-ENT-36 [Scenario]: the inherited comparison uses the three base '
        'fields', () {
      expect(const SeedBareContentFile(), equals(const SeedBareContentFile()));
      expect(
        const SeedBareContentFile().hashCode,
        equals(const SeedBareContentFile().hashCode),
      );
    });

    // TC-ENT-37 [Equivalence partitioning]: each base field decides once.
    for (final MapEntry<String, SeedBareContentFile> row
        in <String, SeedBareContentFile>{
      'fileName': const SeedBareContentFile(fileName: 'NGE-SEED-other'),
      'contentType':
          const SeedBareContentFile(contentType: EpubContentType.xml),
      'contentMimeType':
          const SeedBareContentFile(contentMimeType: 'application/xml'),
    }.entries) {
      test(
          'TC-ENT-37 [Equivalence partitioning]: an inherited comparison on a '
          'differing ${row.key} is unequal', () {
        expect(const SeedBareContentFile(), isNot(equals(row.value)));
        expect(
          const SeedBareContentFile().hashCode,
          isNot(equals(row.value.hashCode)),
        );
      });
    }

    // TC-ENT-38 [Error guessing]: the base checks `other is! EpubContentFile`
    // rather than its own runtime type, so the relation with a subclass is
    // ASYMMETRIC: the base accepts a text file with matching fields, while the
    // text file's own override rejects the bare one. A `==` that is not
    // symmetric breaks `Set` and `Map` membership, so this matters the moment
    // a third subclass appears — it is pinned, not endorsed.
    test(
        'TC-ENT-38 [Error guessing]: the inherited comparison is asymmetric '
        'with a subclass', () {
      const SeedBareContentFile bare = SeedBareContentFile(
        fileName: 'NGE-SEED-shared',
        contentType: EpubContentType.other,
        contentMimeType: 'application/octet-stream',
      );
      final EpubTextContentFile text = seedTextFile(
        fileName: 'NGE-SEED-shared',
        contentType: EpubContentType.other,
        mimeType: 'application/octet-stream',
        content: '',
      );

      expect(bare == text, isTrue);
      expect(text == bare, isFalse);

      expect(bare == unrelatedOperand, isFalse);
      expect(bare == nullOperand, isFalse);
    });
  });

  group('EpubTextContentFile', () {
    // TC-ENT-6 [Error guessing]: the subclass narrows to its own type.
    test('TC-ENT-6 [Error guessing]: a byte file is not a text file', () {
      expect(seedTextFile() == seedByteFile(), isFalse);
      expect(seedTextFile() == unrelatedNumber, isFalse);
    });

    // TC-ENT-7 [Boundary value]: `hash4` is fed the raw values here, not
    // their hash codes — a distinct code path from the base's `hash3`.
    test(
        'TC-ENT-7 [Boundary]: differing content yields a differing '
        'hashCode', () {
      expect(
        seedTextFile().hashCode,
        isNot(equals(seedTextFile(content: 'NGE-SEED other').hashCode)),
      );
    });
  });

  group('EpubByteContentFile', () {
    // TC-ENT-8 [Scenario/use-case]: byte content is compared element-wise, so
    // two distinct lists with the same bytes are equal.
    test('TC-ENT-8 [Scenario]: equal byte content compares equal', () {
      final EpubByteContentFile a = seedByteFile(content: <int>[7, 8, 9]);
      final EpubByteContentFile b = seedByteFile(content: <int>[7, 8, 9]);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    // TC-ENT-9 [Equivalence partitioning]: every operand of the byte file's
    // `&&` chain decides once.
    for (final MapEntry<String, EpubByteContentFile> row
        in <String, EpubByteContentFile>{
      'content': seedByteFile(content: <int>[9, 9, 9]),
      'contentMimeType': seedByteFile(mimeType: 'image/gif'),
      'contentType': seedByteFile(contentType: EpubContentType.imageGif),
      'fileName': seedByteFile(fileName: 'NGE-SEED-other.png'),
    }.entries) {
      test(
          'TC-ENT-9 [Equivalence partitioning]: a differing ${row.key} '
          'breaks equality', () {
        expect(seedByteFile(), isNot(equals(row.value)));
      });
    }

    // TC-ENT-10 [Boundary value]: a zero-byte file is a legal state — an
    // empty archive entry reads as one — and its empty content still hashes
    // and compares, and differs from a file with bytes.
    test('TC-ENT-10 [Boundary]: empty content hashes and compares', () {
      final EpubByteContentFile a = seedByteFile(content: <int>[]);

      expect(a, equals(seedByteFile(content: <int>[])));
      expect(a.hashCode, equals(seedByteFile(content: <int>[]).hashCode));
      expect(a, isNot(equals(seedByteFile())));
    });

    // TC-ENT-11 [Error guessing]: narrows to its own type.
    test('TC-ENT-11 [Error guessing]: a text file is not a byte file', () {
      expect(seedByteFile() == seedTextFile(), isFalse);
      expect(seedByteFile() == nullOperand, isFalse);
    });

    // TC-ENT-39 [Error guessing]: `content` feeds `hashCode` byte by byte.
    // TC-ENT-9 shows two DIFFERING lists compare unequal; this is the half
    // that shows they also hash differently, so a `hashCode` that dropped the
    // bytes would fail here.
    test(
        'TC-ENT-39 [Error guessing]: differing content yields a differing '
        'hashCode', () {
      final EpubByteContentFile a = seedByteFile(content: <int>[1, 2, 3]);
      final EpubByteContentFile b = seedByteFile(content: <int>[9, 9, 9]);

      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });

  group('EpubContent', () {
    // TC-ENT-12 [Scenario/use-case]: the constructor defaults all five maps
    // to empty, which is what makes a bare instance safe to hash.
    test('TC-ENT-12 [Scenario]: the constructor defaults to five empty maps',
        () {
      const EpubContent content = EpubContent();

      expect(content.html, isEmpty);
      expect(content.css, isEmpty);
      expect(content.images, isEmpty);
      expect(content.fonts, isEmpty);
      expect(content.allFiles, isEmpty);
      expect(content.hashCode, isA<int>());
      expect(content, equals(const EpubContent()));
    });

    // TC-ENT-13 [Equivalence partitioning]: each of the five maps is compared,
    // so populating exactly one of them breaks equality — and the populated
    // instance hashes over both keys and values.
    for (final MapEntry<String, EpubContent> row in <String, EpubContent>{
      'html': EpubContent(
        html: <String, EpubTextContentFile>{
          'NGE-SEED-a.xhtml': seedTextFile(),
        },
      ),
      'css': EpubContent(
        css: <String, EpubTextContentFile>{
          'NGE-SEED-a.css': seedTextFile(
            contentType: EpubContentType.css,
            mimeType: 'text/css',
          ),
        },
      ),
      'images': EpubContent(
        images: <String, EpubByteContentFile>{
          'NGE-SEED-a.png': seedByteFile(),
        },
      ),
      'fonts': EpubContent(
        fonts: <String, EpubByteContentFile>{
          'NGE-SEED-a.ttf': seedByteFile(
            contentType: EpubContentType.fontTruetype,
            mimeType: 'font/truetype',
          ),
        },
      ),
      'allFiles': EpubContent(
        allFiles: <String, EpubContentFile>{
          'NGE-SEED-a.xhtml': seedTextFile(),
        },
      ),
    }.entries) {
      test(
          'TC-ENT-13 [Equivalence partitioning]: a populated ${row.key} '
          'breaks equality', () {
        expect(row.value, isNot(equals(const EpubContent())));
        expect(
          row.value.hashCode,
          isNot(equals(const EpubContent().hashCode)),
        );
      });
    }

    // TC-ENT-14 [Scenario/use-case]: two independently built, identically
    // populated contents agree on both `==` and `hashCode`.
    test('TC-ENT-14 [Scenario]: identically populated contents are equal', () {
      EpubContent build() => EpubContent(
            html: <String, EpubTextContentFile>{
              'NGE-SEED-a.xhtml': seedTextFile(),
            },
            css: <String, EpubTextContentFile>{
              'NGE-SEED-a.css': seedTextFile(mimeType: 'text/css'),
            },
            images: <String, EpubByteContentFile>{
              'NGE-SEED-a.png': seedByteFile(),
            },
            fonts: <String, EpubByteContentFile>{
              'NGE-SEED-a.ttf': seedByteFile(mimeType: 'font/truetype'),
            },
            allFiles: <String, EpubContentFile>{
              'NGE-SEED-a.xhtml': seedTextFile(),
            },
          );

      expect(build(), equals(build()));
      expect(build().hashCode, equals(build().hashCode));
    });

    // TC-ENT-15 [Error guessing]: `is!`-guarded, so unrelated operands are
    // rejected without throwing.
    test('TC-ENT-15 [Error guessing]: an unrelated operand is not equal', () {
      expect(const EpubContent() == unrelatedOperand, isFalse);
      expect(const EpubContent() == nullOperand, isFalse);
    });
  });

  group('EpubSchema', () {
    // TC-ENT-16 [Scenario/use-case]: all three fields participate.
    test('TC-ENT-16 [Scenario]: identical schemas are equal', () {
      expect(seedSchema(), equals(seedSchema()));
      expect(seedSchema().hashCode, equals(seedSchema().hashCode));
    });

    // TC-ENT-17 [Equivalence partitioning]: one differing field per run.
    test(
        'TC-ENT-17 [Equivalence partitioning]: a differing '
        'contentDirectoryPath breaks equality', () {
      expect(
        seedSchema(),
        isNot(equals(seedSchema(contentDirectoryPath: 'NGE-SEED-OTHER'))),
      );
    });

    test(
        'TC-ENT-17 [Equivalence partitioning]: a differing package breaks '
        'equality', () {
      final EpubSchema other =
          seedSchema(package: seedPackage(version: EpubVersion.epub3));

      expect(seedSchema(), isNot(equals(other)));
    });

    test(
        'TC-ENT-17 [Equivalence partitioning]: a differing navigation breaks '
        'equality', () {
      final EpubSchema other = seedSchema(
        navigation: seedNavigation(
          docAuthors: const <EpubNavigationDocAuthor>[
            EpubNavigationDocAuthor(authors: <String>['NGE-SEED']),
          ],
        ),
      );

      expect(seedSchema(), isNot(equals(other)));
    });

    // TC-ENT-19 [Error guessing]: `is!`-guarded.
    test('TC-ENT-19 [Error guessing]: an unrelated operand is not equal', () {
      expect(seedSchema() == unrelatedOperand, isFalse);
      expect(seedSchema() == nullOperand, isFalse);
    });
  });

  group('EpubChapter', () {
    // TC-ENT-20 [Scenario/use-case]: every field participates and a nested
    // subchapter list is compared element-wise.
    test('TC-ENT-20 [Scenario]: identical chapter trees are equal', () {
      EpubChapter build() => seedChapter(
            subChapters: <EpubChapter>[
              seedChapter(
                title: 'NGE-SEED Sub',
                contentFileName: 'NGE-SEED-sub.xhtml',
              ),
            ],
          );

      expect(build(), equals(build()));
      expect(build().hashCode, equals(build().hashCode));
      expect(
        build().toString(),
        'Title: NGE-SEED Chapter, Subchapter count: 1',
      );
    });

    // TC-ENT-21 [Equivalence partitioning]: one differing field per run.
    // `anchor` is the one nullable field, so its row is a present anchor
    // against the seed's absent one.
    for (final MapEntry<String, EpubChapter> row in <String, EpubChapter>{
      'title': seedChapter(title: 'NGE-SEED Other'),
      'contentFileName': seedChapter(contentFileName: 'NGE-SEED-other.xhtml'),
      'anchor': seedChapter(anchor: 'NGE-SEED-anchor'),
      'htmlContent': seedChapter(htmlContent: '<p>NGE-SEED other</p>'),
      'subChapters': seedChapter(
        subChapters: <EpubChapter>[seedChapter(title: 'NGE-SEED Sub')],
      ),
      'otherContentFileNames': seedChapter(
        otherContentFileNames: const <String>['NGE-SEED-part2.xhtml'],
      ),
    }.entries) {
      test(
          'TC-ENT-21 [Equivalence partitioning]: a differing ${row.key} '
          'breaks equality', () {
        expect(seedChapter(), isNot(equals(row.value)));
      });
    }

    // TC-ENT-22 [Error guessing]: `otherContentFileNames` is compared with
    // `listsEqual` and hashed by element, like every other collection field.
    // Two chapters built separately generally hold two distinct lists, so a
    // comparison by list identity would make two chapters with identical
    // data unequal and hash them apart. Both halves are asserted: equal names in two distinct
    // lists compare equal AND hash alike, while differing names still
    // separate the chapters.
    test(
        'TC-ENT-22 [Error guessing]: otherContentFileNames is compared by '
        'value, not by list identity', () {
      final List<String> firstNames = <String>['NGE-SEED-part2.xhtml'];
      final List<String> secondNames = <String>['NGE-SEED-part2.xhtml'];
      final EpubChapter a = seedChapter(otherContentFileNames: firstNames);
      final EpubChapter b = seedChapter(otherContentFileNames: secondNames);

      expect(
          identical(a.otherContentFileNames, b.otherContentFileNames), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));

      // The field still decides equality, and the hash, when the names
      // differ.
      final EpubChapter c =
          seedChapter(otherContentFileNames: <String>['NGE-SEED-part3.xhtml']);
      expect(a, isNot(equals(c)));
      expect(a.hashCode, isNot(equals(c.hashCode)));
    });

    // TC-ENT-23 [Error guessing]: `is!`-guarded.
    test('TC-ENT-23 [Error guessing]: an unrelated operand is not equal', () {
      expect(seedChapter() == unrelatedOperand, isFalse);
      expect(seedChapter() == nullOperand, isFalse);
    });

    // TC-ENT-24 [Boundary value]: a chapter built from the required fields
    // alone defaults to no subchapters, no anchor and no split parts, so it
    // prints, and equals a twin built the same way.
    test(
        'TC-ENT-24 [Boundary]: a chapter built from its required fields '
        'prints a subchapter count of zero', () {
      const EpubChapter chapter = EpubChapter(
        title: 'NGE-SEED Bare',
        contentFileName: 'NGE-SEED-bare.xhtml',
        htmlContent: '',
      );

      expect(chapter.anchor, isNull);
      expect(chapter.subChapters, isEmpty);
      expect(chapter.otherContentFileNames, isEmpty);
      expect(chapter.toString(), 'Title: NGE-SEED Bare, Subchapter count: 0');
      expect(
        chapter,
        equals(seedChapter(
          title: 'NGE-SEED Bare',
          contentFileName: 'NGE-SEED-bare.xhtml',
          htmlContent: '',
        )),
      );
    });

    // TC-ENT-40 [Error guessing]: `subChapters` feeds `hashCode` by element.
    // TC-ENT-21 shows two DIFFERING lists compare unequal; this is the half
    // that shows they also hash differently.
    test(
        'TC-ENT-40 [Error guessing]: differing subChapters yields a '
        'differing hashCode', () {
      final EpubChapter a =
          seedChapter(subChapters: <EpubChapter>[seedChapter(title: 'One')]);
      final EpubChapter b =
          seedChapter(subChapters: <EpubChapter>[seedChapter(title: 'Two')]);

      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });

  group('EpubBook', () {
    // TC-ENT-26 [Scenario/use-case]: a fully populated book equals its twin,
    // cover image included — `getBytes()` is compared element-wise.
    test('TC-ENT-26 [Scenario]: identical books are equal, cover included', () {
      final EpubBook a = seedBook(coverImage: seedImage(7));
      final EpubBook b = seedBook(coverImage: seedImage(7));

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    // TC-ENT-27 [Equivalence partitioning]: one differing field per run.
    for (final MapEntry<String, EpubBook> row in <String, EpubBook>{
      'title': seedBook(title: 'NGE-SEED Other'),
      'authorList': seedBook(authorList: <String>['NGE-SEED Other']),
      'schema': seedBook(schema: seedSchema(contentDirectoryPath: 'OTHER')),
      'content': seedBook(
        content: EpubContent(
          html: <String, EpubTextContentFile>{'NGE-SEED': seedTextFile()},
        ),
      ),
      'chapters': seedBook(chapters: <EpubChapter>[]),
    }.entries) {
      test(
          'TC-ENT-27 [Equivalence partitioning]: a differing ${row.key} '
          'breaks equality', () {
        expect(seedBook(), isNot(equals(row.value)));
      });
    }

    // TC-ENT-28 [Equivalence partitioning]: two covers that decode to
    // different pixels are unequal — the `getBytes()` comparison, not identity.
    test(
        'TC-ENT-28 [Equivalence partitioning]: differing cover pixels break '
        'equality', () {
      final EpubBook a = seedBook(coverImage: seedImage(7));
      final EpubBook b = seedBook(coverImage: seedImage(200));

      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    // TC-ENT-29 [Boundary value]: two coverless books take the both-null
    // branch of the cover comparison.
    test('TC-ENT-29 [Boundary]: two coverless books are equal', () {
      expect(seedBook(), equals(seedBook()));
      expect(seedBook().hashCode, equals(seedBook().hashCode));
    });

    // TC-ENT-30 [Error guessing]: a cover on one side only. The cover
    // comparison must not dereference the absent side: a missing cover is a
    // difference, so both directions answer false, and `==` stays
    // symmetric.
    test(
        'TC-ENT-30 [Error guessing]: a one-sided cover compares unequal '
        'instead of throwing', () {
      final EpubBook withCover = seedBook(coverImage: seedImage(7));
      final EpubBook withoutCover = seedBook();

      expect(withCover == withoutCover, isFalse);
      expect(withoutCover == withCover, isFalse);
    });

    // TC-ENT-31 [Error guessing]: `is`-guarded, so an unrelated operand is
    // rejected rather than throwing.
    test('TC-ENT-31 [Error guessing]: an unrelated operand is not equal', () {
      expect(seedBook() == unrelatedOperand, isFalse);
      expect(seedBook() == nullOperand, isFalse);
    });

    // TC-ENT-32 [Boundary value]: the emptiest book — no title, no author,
    // no chapter, no cover, which is how a package missing all of them
    // reads — still hashes and equals another.
    test('TC-ENT-32 [Boundary]: an empty book hashes and equals another', () {
      EpubBook build() => seedBook(
            title: '',
            authorList: <String>[],
            chapters: <EpubChapter>[],
          );

      expect(build().hashCode, equals(build().hashCode));
      expect(build(), equals(build()));
      expect(build(), isNot(equals(seedBook())));
    });

    // TC-ENT-41 [Error guessing]: `authorList` feeds `hashCode` by element.
    // TC-ENT-27 shows a differing authorList or chapters breaks equality;
    // these two show that DIFFERING values of either field also hash
    // differently.
    test(
        'TC-ENT-41 [Error guessing]: differing authorList yields a differing '
        'hashCode', () {
      final EpubBook a = seedBook(authorList: <String>['NGE-SEED One']);
      final EpubBook b = seedBook(authorList: <String>['NGE-SEED Two']);

      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test(
        'TC-ENT-42 [Error guessing]: differing chapters yields a differing '
        'hashCode', () {
      final EpubBook a =
          seedBook(chapters: <EpubChapter>[seedChapter(title: 'One')]);
      final EpubBook b =
          seedBook(chapters: <EpubChapter>[seedChapter(title: 'Two')]);

      expect(a.hashCode, isNot(equals(b.hashCode)));
    });
  });

  group('Entities as produced by EpubReader.readBook', () {
    // The one fixture in this file that goes through the public entry point,
    // so the equality contract is checked over values the reader actually
    // produces rather than hand-built ones.
    const String opf = '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
        'unique-identifier="uid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>NGE-SEED Entities Book</dc:title>'
        '<dc:creator>NGE-SEED Author</dc:creator>'
        '</metadata>'
        '<manifest>'
        '<item id="ncx" href="toc.ncx" '
        'media-type="application/x-dtbncx+xml"/>'
        '<item id="ch1" href="chapter1.xhtml" '
        'media-type="application/xhtml+xml"/>'
        '<item id="css" href="style.css" media-type="text/css"/>'
        '</manifest>'
        '<spine toc="ncx"><itemref idref="ch1"/></spine>'
        '</package>';

    const String ncx = '<?xml version="1.0" encoding="UTF-8"?>'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
        '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-ENT"/></head>'
        '<docTitle><text>NGE-SEED Entities Book</text></docTitle>'
        '<navMap>'
        '<navPoint id="np-1" playOrder="1">'
        '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
        '<content src="chapter1.xhtml"/>'
        '</navPoint>'
        '</navMap>'
        '</ncx>';

    Uint8List build(String body) => buildEpubArchive(
          opfPath: 'OEBPS/content.opf',
          textEntries: <String, String>{
            'OEBPS/content.opf': opf,
            'OEBPS/toc.ncx': ncx,
            'OEBPS/chapter1.xhtml': seedXhtml(body),
            'OEBPS/style.css': 'body { color: #000; }',
          },
        );

    // TC-ENT-33 [Scenario/use-case]: reading one archive twice produces two
    // graphs that compare equal all the way down — schema, content, chapters
    // and the book itself. Each read builds every chapter, and every
    // collection inside the graph, afresh, so only element-wise comparison
    // all the way down lets a book equal itself across two reads of the same
    // bytes.
    test('TC-ENT-33 [Scenario]: two reads of one archive produce equal books',
        () async {
      final EpubBook first =
          await const EpubReader().readBook(build('NGE-SEED-A'));
      final EpubBook second =
          await const EpubReader().readBook(build('NGE-SEED-A'));

      expect(first.schema, equals(second.schema));
      expect(first.content, equals(second.content));
      expect(first.content.allFiles, hasLength(3));
      expect(
        first.content.html['chapter1.xhtml'],
        equals(second.content.html['chapter1.xhtml']),
      );
      expect(
        first.content.css['style.css'],
        equals(second.content.css['style.css']),
      );

      expect(first.chapters, equals(second.chapters));
      expect(first, equals(second));
      expect(first.hashCode, equals(second.hashCode));

      // The chapters are identical in every field the reader populates.
      expect(first.chapters.single.title, second.chapters.single.title);
      expect(
        first.chapters.single.htmlContent,
        second.chapters.single.htmlContent,
      );
      expect(
        first.chapters.single.toString(),
        'Title: NGE-SEED Chapter One, Subchapter count: 0',
      );
    });

    // TC-ENT-34 [Equivalence partitioning]: a differing chapter body changes
    // the content entity too, so the inequality comes from
    // `EpubContent.==` doing real work, not from the chapter alone.
    test(
        'TC-ENT-34 [Equivalence partitioning]: a differing chapter body makes '
        'the content unequal', () async {
      final EpubBook first =
          await const EpubReader().readBook(build('NGE-SEED-A'));
      final EpubBook second =
          await const EpubReader().readBook(build('NGE-SEED-B'));

      expect(first.content, isNot(equals(second.content)));
      expect(first.schema, equals(second.schema));
      expect(
        first.content.html['chapter1.xhtml']!.content,
        isNot(equals(second.content.html['chapter1.xhtml']!.content)),
      );
    });

    // TC-ENT-35 [Boundary value]: a book read from an archive with no cover
    // has a null `coverImage`, which is the side of TC-ENT-30's branch the
    // read path actually takes.
    test('TC-ENT-35 [Boundary]: a coverless archive yields a null coverImage',
        () async {
      final EpubBook book =
          await const EpubReader().readBook(build('NGE-SEED-A'));

      expect(book.coverImage, isNull);
      expect(book.title, 'NGE-SEED Entities Book');
      expect(book.authorList, <String>['NGE-SEED Author']);
    });
  });
}
