// The loaded-value entities — `EpubBook`, `EpubChapter`, `EpubContent`,
// `EpubContentFile` and its two subclasses, and `EpubSchema`.
//
// These are plain data holders whose only behaviour is `==`, `hashCode` and
// `toString`, so they are exercised by direct construction; the archive-backed
// half of the package is covered through `EpubReader` in the reader suites.
//
// Two upstream defects shape this file and are pinned AS THEY BEHAVE TODAY,
// each in a test that says so: `EpubChapter` compares
// `OtherContentFileNames` by identity (TC-ENT-22), and `EpubBook.==` throws
// when exactly one side has a cover (TC-ENT-30).
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
  String? fileName = 'NGE-SEED-chapter.xhtml',
  String? content = 'NGE-SEED body',
  EpubContentType? contentType = EpubContentType.XHTML_1_1,
  String? mimeType = 'application/xhtml+xml',
}) =>
    EpubTextContentFile()
      ..FileName = fileName
      ..Content = content
      ..ContentType = contentType
      ..ContentMimeType = mimeType;

EpubByteContentFile seedByteFile({
  String? fileName = 'NGE-SEED-cover.png',
  List<int>? content = const <int>[1, 2, 3],
  EpubContentType? contentType = EpubContentType.IMAGE_PNG,
  String? mimeType = 'image/png',
}) =>
    EpubByteContentFile()
      ..FileName = fileName
      ..Content = content
      ..ContentType = contentType
      ..ContentMimeType = mimeType;

/// [otherContentFileNames] defaults to the canonical `const <String>[]` rather
/// than the field's own fresh `[]`, because `EpubChapter.==` compares that
/// field by identity — see TC-ENT-22. Every other test in this group wants to
/// exercise the REST of the equality chain, which is only reachable once both
/// sides share one list instance.
EpubChapter seedChapter({
  String? title = 'NGE-SEED Chapter',
  String? contentFileName = 'NGE-SEED-chapter.xhtml',
  String? anchor,
  String? htmlContent = '<p>NGE-SEED</p>',
  List<EpubChapter>? subChapters = const <EpubChapter>[],
  List<String> otherContentFileNames = const <String>[],
}) =>
    EpubChapter()
      ..Title = title
      ..ContentFileName = contentFileName
      ..Anchor = anchor
      ..HtmlContent = htmlContent
      ..SubChapters = subChapters
      ..OtherContentFileNames = otherContentFileNames;

EpubSchema seedSchema({String? contentDirectoryPath = 'OEBPS'}) => EpubSchema()
  ..ContentDirectoryPath = contentDirectoryPath
  ..Package = (EpubPackage()..Version = EpubVersion.Epub2)
  ..Navigation = EpubNavigation();

EpubBook seedBook() => EpubBook()
  ..Title = 'NGE-SEED Book'
  ..Author = 'NGE-SEED Author'
  ..AuthorList = <String?>['NGE-SEED Author']
  ..Schema = seedSchema()
  ..Content = EpubContent()
  ..Chapters = <EpubChapter>[seedChapter()];

/// The smallest possible concrete `EpubContentFile`.
///
/// Both shipped subclasses override `==` and `hashCode`, so the base
/// implementations are unreachable from anything this package constructs — see
/// TC-ENT-36. They are nonetheless public API: `EpubContentFile` is exported,
/// and any further subclass inherits them. This class is what lets the base
/// behaviour be pinned at all.
class SeedBareContentFile extends EpubContentFile {
  SeedBareContentFile({
    String? fileName = 'NGE-SEED-bare',
    EpubContentType? contentType = EpubContentType.OTHER,
    String? mimeType = 'application/octet-stream',
  }) {
    FileName = fileName;
    ContentType = contentType;
    ContentMimeType = mimeType;
  }
}

/// An operand of an unrelated type, held as `Object` so each comparison below
/// is a real runtime check. Typing it `Object` rather than inlining a literal
/// is what keeps these tests free of an `unrelated_type_equality_checks`
/// suppression, which this package's lint forbids outright.
final Object unrelatedOperand = 'NGE-SEED-not-a-domain-object';

/// A null operand, typed nullable so the analyzer does not fold the comparison
/// away as a statically-known mismatch. Every class under test must answer
/// false here rather than throw.
final Object? nullOperand = null;

/// The same idea as [unrelatedOperand], for the one site that needs a
/// non-String operand.
final Object unrelatedNumber = 42;

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
      'FileName': seedTextFile(fileName: 'NGE-SEED-other.xhtml'),
      'ContentType': seedTextFile(contentType: EpubContentType.XML),
      'ContentMimeType': seedTextFile(mimeType: 'application/xml'),
      'Content': seedTextFile(content: 'NGE-SEED different body'),
    }.entries) {
      test(
          'TC-ENT-2 [Equivalence partitioning]: a differing ${row.key} '
          'breaks equality', () {
        expect(seedTextFile(), isNot(equals(row.value)));
      });
    }

    // TC-ENT-3 [Error guessing]: the entity classes use `is!`, so an unrelated
    // operand is rejected rather than throwing — unlike the OPF schema
    // classes, which cast (see TC-OPF-1).
    test('TC-ENT-3 [Error guessing]: an unrelated operand is not equal', () {
      expect(seedTextFile() == unrelatedOperand, isFalse);
      expect(seedTextFile() == nullOperand, isFalse);
    });

    // TC-ENT-4 [Boundary value]: an all-null file is still a valid operand on
    // both sides — `hash3` is fed `null.hashCode` three times.
    test('TC-ENT-4 [Boundary]: two all-null text files are equal', () {
      final EpubTextContentFile a = EpubTextContentFile();
      final EpubTextContentFile b = EpubTextContentFile();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    // TC-ENT-5 [Scenario/use-case]: both subclasses override `==` and narrow
    // to their own runtime type, so a text file and a byte file are unequal in
    // BOTH directions even when the three base fields match. The base
    // implementation is therefore never what decides between two subclass
    // instances.
    test('TC-ENT-5 [Scenario]: the two subclasses reject each other', () {
      final EpubContentFile text = seedTextFile(
        fileName: 'NGE-SEED-shared',
        contentType: EpubContentType.OTHER,
        mimeType: 'application/octet-stream',
        content: null,
      );
      final EpubContentFile bytes = seedByteFile(
        fileName: 'NGE-SEED-shared',
        contentType: EpubContentType.OTHER,
        mimeType: 'application/octet-stream',
        content: null,
      );

      expect(bytes, isNot(equals(text)));
      expect(text, isNot(equals(bytes)));
      expect(text.FileName, equals(bytes.FileName));
      expect(text.ContentType, equals(bytes.ContentType));
      expect(text.ContentMimeType, equals(bytes.ContentMimeType));
    });

    // TC-ENT-36 [Scenario/use-case]: the base's own `==` and `hashCode`, which
    // no instance this package builds can reach — both shipped subclasses
    // override them. Exercised through `SeedBareContentFile` so the inherited
    // behaviour is pinned for any future subclass.
    test(
        'TC-ENT-36 [Scenario]: the inherited comparison uses the three base '
        'fields', () {
      expect(SeedBareContentFile(), equals(SeedBareContentFile()));
      expect(
        SeedBareContentFile().hashCode,
        equals(SeedBareContentFile().hashCode),
      );
    });

    // TC-ENT-37 [Equivalence partitioning]: each base field decides once.
    for (final MapEntry<String, SeedBareContentFile> row
        in <String, SeedBareContentFile>{
      'FileName': SeedBareContentFile(fileName: 'NGE-SEED-other'),
      'ContentType': SeedBareContentFile(contentType: EpubContentType.XML),
      'ContentMimeType': SeedBareContentFile(mimeType: 'application/xml'),
    }.entries) {
      test(
          'TC-ENT-37 [Equivalence partitioning]: an inherited comparison on a '
          'differing ${row.key} is unequal', () {
        expect(SeedBareContentFile(), isNot(equals(row.value)));
        expect(
          SeedBareContentFile().hashCode,
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
      final SeedBareContentFile bare = SeedBareContentFile(
        fileName: 'NGE-SEED-shared',
        contentType: EpubContentType.OTHER,
        mimeType: 'application/octet-stream',
      );
      final EpubTextContentFile text = seedTextFile(
        fileName: 'NGE-SEED-shared',
        contentType: EpubContentType.OTHER,
        mimeType: 'application/octet-stream',
        content: null,
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
      'Content': seedByteFile(content: <int>[9, 9, 9]),
      'ContentMimeType': seedByteFile(mimeType: 'image/gif'),
      'ContentType': seedByteFile(contentType: EpubContentType.IMAGE_GIF),
      'FileName': seedByteFile(fileName: 'NGE-SEED-other.png'),
    }.entries) {
      test(
          'TC-ENT-9 [Equivalence partitioning]: a differing ${row.key} '
          'breaks equality', () {
        expect(seedByteFile(), isNot(equals(row.value)));
      });
    }

    // TC-ENT-10 [Boundary value]: null content is a legal state (nothing has
    // been read yet) and hashes through the `?? [0]` fallback.
    test('TC-ENT-10 [Boundary]: null content hashes and compares', () {
      final EpubByteContentFile a = seedByteFile(content: null);

      expect(a, equals(seedByteFile(content: null)));
      expect(a.hashCode, isA<int>());
      expect(a, isNot(equals(seedByteFile())));
    });

    // TC-ENT-11 [Error guessing]: narrows to its own type.
    test('TC-ENT-11 [Error guessing]: a text file is not a byte file', () {
      expect(seedByteFile() == seedTextFile(), isFalse);
      expect(seedByteFile() == nullOperand, isFalse);
    });
  });

  group('EpubContent', () {
    // TC-ENT-12 [Scenario/use-case]: the constructor initialises all five maps
    // to empty, which is what makes a bare instance safe to hash.
    test('TC-ENT-12 [Scenario]: the constructor initialises five empty maps',
        () {
      final EpubContent content = EpubContent();

      expect(content.Html, isEmpty);
      expect(content.Css, isEmpty);
      expect(content.Images, isEmpty);
      expect(content.Fonts, isEmpty);
      expect(content.AllFiles, isEmpty);
      expect(content.hashCode, isA<int>());
      expect(content, equals(EpubContent()));
    });

    // TC-ENT-13 [Equivalence partitioning]: each of the five maps is compared,
    // so populating exactly one of them breaks equality — and the populated
    // instance hashes over both keys and values.
    for (final String bucket in <String>[
      'Html',
      'Css',
      'Images',
      'Fonts',
      'AllFiles',
    ]) {
      test(
          'TC-ENT-13 [Equivalence partitioning]: a populated $bucket breaks '
          'equality', () {
        final EpubContent populated = EpubContent();
        switch (bucket) {
          case 'Html':
            populated.Html!['NGE-SEED-a.xhtml'] = seedTextFile();
          case 'Css':
            populated.Css!['NGE-SEED-a.css'] = seedTextFile(
              contentType: EpubContentType.CSS,
              mimeType: 'text/css',
            );
          case 'Images':
            populated.Images!['NGE-SEED-a.png'] = seedByteFile();
          case 'Fonts':
            populated.Fonts!['NGE-SEED-a.ttf'] = seedByteFile(
              contentType: EpubContentType.FONT_TRUETYPE,
              mimeType: 'font/truetype',
            );
          case 'AllFiles':
            populated.AllFiles!['NGE-SEED-a.xhtml'] = seedTextFile();
        }

        expect(populated, isNot(equals(EpubContent())));
        expect(populated.hashCode, isNot(equals(EpubContent().hashCode)));
      });
    }

    // TC-ENT-14 [Scenario/use-case]: two independently built, identically
    // populated contents agree on both `==` and `hashCode`.
    test('TC-ENT-14 [Scenario]: identically populated contents are equal', () {
      EpubContent build() => EpubContent()
        ..Html!['NGE-SEED-a.xhtml'] = seedTextFile()
        ..Css!['NGE-SEED-a.css'] = seedTextFile(mimeType: 'text/css')
        ..Images!['NGE-SEED-a.png'] = seedByteFile()
        ..Fonts!['NGE-SEED-a.ttf'] = seedByteFile(mimeType: 'font/truetype')
        ..AllFiles!['NGE-SEED-a.xhtml'] = seedTextFile();

      expect(build(), equals(build()));
      expect(build().hashCode, equals(build().hashCode));
    });

    // TC-ENT-15 [Error guessing]: `is!`-guarded, so unrelated operands are
    // rejected without throwing.
    test('TC-ENT-15 [Error guessing]: an unrelated operand is not equal', () {
      expect(EpubContent() == unrelatedOperand, isFalse);
      expect(EpubContent() == nullOperand, isFalse);
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
        'ContentDirectoryPath breaks equality', () {
      expect(
        seedSchema(),
        isNot(equals(seedSchema(contentDirectoryPath: 'NGE-SEED-OTHER'))),
      );
    });

    test(
        'TC-ENT-17 [Equivalence partitioning]: a differing Package breaks '
        'equality', () {
      final EpubSchema other = seedSchema()
        ..Package = (EpubPackage()..Version = EpubVersion.Epub3);

      expect(seedSchema(), isNot(equals(other)));
    });

    test(
        'TC-ENT-17 [Equivalence partitioning]: a differing Navigation breaks '
        'equality', () {
      final EpubSchema other = seedSchema()
        ..Navigation = (EpubNavigation()
          ..DocAuthors = <EpubNavigationDocAuthor>[
            EpubNavigationDocAuthor()..Authors = <String>['NGE-SEED'],
          ]);

      expect(seedSchema(), isNot(equals(other)));
    });

    // TC-ENT-18 [Boundary value]: an all-null schema hashes and compares.
    test('TC-ENT-18 [Boundary]: an empty schema is equal to another', () {
      expect(EpubSchema(), equals(EpubSchema()));
      expect(EpubSchema().hashCode, equals(EpubSchema().hashCode));
    });

    // TC-ENT-19 [Error guessing]: `is!`-guarded.
    test('TC-ENT-19 [Error guessing]: an unrelated operand is not equal', () {
      expect(EpubSchema() == unrelatedOperand, isFalse);
      expect(EpubSchema() == nullOperand, isFalse);
    });
  });

  group('EpubChapter', () {
    // TC-ENT-20 [Scenario/use-case]: with the identity-compared field held
    // constant (see TC-ENT-22), every other field participates and a nested
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
    for (final MapEntry<String, EpubChapter> row in <String, EpubChapter>{
      'Title': seedChapter(title: 'NGE-SEED Other'),
      'ContentFileName': seedChapter(contentFileName: 'NGE-SEED-other.xhtml'),
      'Anchor': seedChapter(anchor: 'NGE-SEED-anchor'),
      'HtmlContent': seedChapter(htmlContent: '<p>NGE-SEED other</p>'),
      'SubChapters': seedChapter(
        subChapters: <EpubChapter>[seedChapter(title: 'NGE-SEED Sub')],
      ),
      'OtherContentFileNames': seedChapter(
        otherContentFileNames: const <String>['NGE-SEED-part2.xhtml'],
      ),
    }.entries) {
      test(
          'TC-ENT-21 [Equivalence partitioning]: a differing ${row.key} '
          'breaks equality', () {
        expect(seedChapter(), isNot(equals(row.value)));
      });
    }

    // TC-ENT-22 [Error guessing]: KNOWN DEFECT, and the widest-reaching one in
    // this file. `OtherContentFileNames` is compared with `==` on two `List`
    // objects — identity — while every other collection field goes through
    // `listsEqual`. Because the field initialiser hands every instance its own
    // fresh `[]`, two chapters built the ordinary way are NEVER equal and
    // never share a `hashCode`, however identical their data. That propagates:
    // `EpubBook.==` compares `Chapters` element-wise, so it inherits the same
    // result (TC-ENT-33). Pinned as it behaves today; when the comparison
    // becomes `listsEqual`, the first two expectations here flip to `equals`.
    test(
        'TC-ENT-22 [Error guessing]: KNOWN DEFECT — OtherContentFileNames is '
        'compared by identity, so default-built chapters are never equal', () {
      final EpubChapter a = EpubChapter()..SubChapters = const <EpubChapter>[];
      final EpubChapter b = EpubChapter()..SubChapters = const <EpubChapter>[];

      expect(a.OtherContentFileNames, equals(b.OtherContentFileNames));
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));

      // Sharing one list instance is the only way two chapters compare equal.
      final List<String> shared = <String>['NGE-SEED-part2.xhtml'];
      expect(
        seedChapter(otherContentFileNames: shared),
        equals(seedChapter(otherContentFileNames: shared)),
      );
    });

    // TC-ENT-23 [Error guessing]: `is!`-guarded.
    test('TC-ENT-23 [Error guessing]: an unrelated operand is not equal', () {
      expect(seedChapter() == unrelatedOperand, isFalse);
      expect(seedChapter() == nullOperand, isFalse);
    });

    // TC-ENT-24 [Error guessing]: KNOWN DEFECT. `toString` dereferences
    // `SubChapters!` unguarded, so a chapter that has not been through
    // `EpubReader.readChapters` — which always assigns a list — cannot be
    // printed. Pinned as it behaves today; when the `!` is guarded, this test
    // must change to assert the rendered string.
    test(
        'TC-ENT-24 [Error guessing]: KNOWN DEFECT — toString throws on null '
        'SubChapters', () {
      expect(EpubChapter().toString, throwsA(isA<TypeError>()));
    });

    // TC-ENT-25 [Boundary value]: a null subchapter list still hashes (the
    // `?? [0]` fallback) and still compares, so only `toString` is affected by
    // TC-ENT-24.
    test('TC-ENT-25 [Boundary]: null SubChapters hashes and compares', () {
      final List<String> shared = <String>[];
      final EpubChapter a = seedChapter(
        subChapters: null,
        otherContentFileNames: shared,
      );

      expect(a.hashCode, isA<int>());
      expect(
        a,
        equals(
          seedChapter(subChapters: null, otherContentFileNames: shared),
        ),
      );
      expect(a, isNot(equals(seedChapter(otherContentFileNames: shared))));
    });
  });

  group('EpubBook', () {
    // TC-ENT-26 [Scenario/use-case]: a fully populated book equals its twin,
    // cover image included — `getBytes()` is compared element-wise.
    test('TC-ENT-26 [Scenario]: identical books are equal, cover included', () {
      final EpubBook a = seedBook()..CoverImage = seedImage(7);
      final EpubBook b = seedBook()..CoverImage = seedImage(7);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    // TC-ENT-27 [Equivalence partitioning]: one differing field per run.
    for (final MapEntry<String, EpubBook> row in <String, EpubBook>{
      'Title': seedBook()..Title = 'NGE-SEED Other',
      'Author': seedBook()..Author = 'NGE-SEED Other',
      'AuthorList': seedBook()..AuthorList = <String?>['NGE-SEED Other'],
      'Schema': seedBook()..Schema = seedSchema(contentDirectoryPath: 'OTHER'),
      'Content': seedBook()
        ..Content = (EpubContent()..Html!['NGE-SEED'] = seedTextFile()),
      'Chapters': seedBook()..Chapters = <EpubChapter>[],
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
      final EpubBook a = seedBook()..CoverImage = seedImage(7);
      final EpubBook b = seedBook()..CoverImage = seedImage(200);

      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    // TC-ENT-29 [Boundary value]: two coverless books take the
    // `CoverImage == null && other.CoverImage == null` short circuit.
    test('TC-ENT-29 [Boundary]: two coverless books are equal', () {
      expect(seedBook(), equals(seedBook()));
      expect(seedBook().hashCode, equals(seedBook().hashCode));
    });

    // TC-ENT-30 [Error guessing]: KNOWN DEFECT. When exactly one side has a
    // cover, the null-pair short circuit fails and the expression falls
    // through to `CoverImage!.getBytes()` — which throws instead of returning
    // false. It throws in BOTH directions: the `!` that fires is whichever
    // side is null. Pinned as it behaves today; the fix makes both directions
    // return `false` and this test must be rewritten then.
    test(
        'TC-ENT-30 [Error guessing]: KNOWN DEFECT — a one-sided cover throws '
        'instead of comparing unequal', () {
      final EpubBook withCover = seedBook()..CoverImage = seedImage(7);
      final EpubBook withoutCover = seedBook();

      expect(() => withCover == withoutCover, throwsA(isA<TypeError>()));
      expect(() => withoutCover == withCover, throwsA(isA<TypeError>()));
    });

    // TC-ENT-31 [Error guessing]: `is!`-guarded, so the type check itself is
    // safe — the throw in TC-ENT-30 is strictly about the cover.
    test('TC-ENT-31 [Error guessing]: an unrelated operand is not equal', () {
      expect(seedBook() == unrelatedOperand, isFalse);
      expect(seedBook() == nullOperand, isFalse);
    });

    // TC-ENT-32 [Boundary value]: a bare book — every field null — still
    // hashes, through the three `?? [0]` fallbacks.
    test('TC-ENT-32 [Boundary]: a bare book hashes and equals another', () {
      expect(EpubBook().hashCode, isA<int>());
      expect(EpubBook(), equals(EpubBook()));
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
    // graphs whose schema and content halves compare equal — and whose
    // chapters do NOT, because `readChapters` builds each `EpubChapter` fresh
    // and never assigns `OtherContentFileNames`, so TC-ENT-22's identity
    // comparison decides. The book therefore never equals itself across two
    // reads. This is the defect's user-visible consequence, pinned as it
    // behaves today; fixing TC-ENT-22 turns all four expectations positive.
    test(
        'TC-ENT-33 [Scenario]: two reads of one archive agree on schema and '
        'content but not on chapters', () async {
      final EpubBook first = await EpubReader.readBook(build('NGE-SEED-A'));
      final EpubBook second = await EpubReader.readBook(build('NGE-SEED-A'));

      expect(first.Schema, equals(second.Schema));
      expect(first.Content, equals(second.Content));
      expect(first.Content!.AllFiles, hasLength(3));
      expect(
        first.Content!.Html!['chapter1.xhtml'],
        equals(second.Content!.Html!['chapter1.xhtml']),
      );
      expect(
        first.Content!.Css!['style.css'],
        equals(second.Content!.Css!['style.css']),
      );

      expect(first.Chapters, isNot(equals(second.Chapters)));
      expect(first, isNot(equals(second)));

      // The chapters are identical in every field the reader populates; only
      // the list identity differs.
      expect(first.Chapters!.single.Title, second.Chapters!.single.Title);
      expect(
        first.Chapters!.single.HtmlContent,
        second.Chapters!.single.HtmlContent,
      );
      expect(
        first.Chapters!.single.toString(),
        'Title: NGE-SEED Chapter One, Subchapter count: 0',
      );
    });

    // TC-ENT-34 [Equivalence partitioning]: a differing chapter body changes
    // the content entity too, so the inequality is not merely the TC-ENT-33
    // artefact — `EpubContent.==` is doing real work here.
    test(
        'TC-ENT-34 [Equivalence partitioning]: a differing chapter body makes '
        'the content unequal', () async {
      final EpubBook first = await EpubReader.readBook(build('NGE-SEED-A'));
      final EpubBook second = await EpubReader.readBook(build('NGE-SEED-B'));

      expect(first.Content, isNot(equals(second.Content)));
      expect(first.Schema, equals(second.Schema));
      expect(
        first.Content!.Html!['chapter1.xhtml']!.Content,
        isNot(equals(second.Content!.Html!['chapter1.xhtml']!.Content)),
      );
    });

    // TC-ENT-35 [Boundary value]: a book read from an archive with no cover
    // has a null `CoverImage`, which is the side of TC-ENT-30's branch the
    // read path actually takes.
    test('TC-ENT-35 [Boundary]: a coverless archive yields a null CoverImage',
        () async {
      final EpubBook book = await EpubReader.readBook(build('NGE-SEED-A'));

      expect(book.CoverImage, isNull);
      expect(book.Title, 'NGE-SEED Entities Book');
      expect(book.Author, 'NGE-SEED Author');
      expect(book.AuthorList, <String>['NGE-SEED Author']);
    });
  });
}
