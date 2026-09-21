// The OPF schema value types — `EpubPackage` and everything it holds:
// metadata and its six sub-types, manifest, spine, guide.
//
// These are plain data holders, so they are exercised by direct construction;
// `package_reader_test.dart` covers how the reader fills them. Two traits run
// through the whole layer and are checked once each rather than per class:
//
//   * every `==` here answers false for an unrelated operand (TC-OPF-1). They
//     used to open with `other as X?` — a CAST, not an `is` check — and threw
//     a `TypeError`; that is fixed, and TC-OPF-1 is now its regression guard.
//   * several `hashCode` getters dereference their list fields with `!`, so a
//     bare instance cannot be hashed (TC-OPF-2). Still pinned AS IT BEHAVES
//     TODAY, and that test says what must change when it is fixed.
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_contributor.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_date.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_meta.dart';
import 'package:test/test.dart';

EpubMetadataCreator seedCreator({
  String? creator = 'NGE-SEED Author',
  String? fileAs = 'Author, NGE-SEED',
  String? role = 'aut',
}) =>
    EpubMetadataCreator()
      ..Creator = creator
      ..FileAs = fileAs
      ..Role = role;

EpubMetadataContributor seedContributor({
  String? contributor = 'NGE-SEED Contributor',
  String? fileAs = 'Contributor, NGE-SEED',
  String? role = 'edt',
}) =>
    EpubMetadataContributor()
      ..Contributor = contributor
      ..FileAs = fileAs
      ..Role = role;

EpubMetadataDate seedDate({
  String? date = '2026-09-21',
  String? event = 'publication',
}) =>
    EpubMetadataDate()
      ..Date = date
      ..Event = event;

EpubMetadataIdentifier seedIdentifier({
  String? id = 'uid',
  String? scheme = 'URN',
  String? identifier = 'urn:uuid:NGE-SEED-OPF',
}) =>
    EpubMetadataIdentifier()
      ..Id = id
      ..Scheme = scheme
      ..Identifier = identifier;

EpubMetadataMeta seedMeta({
  String? name = 'cover',
  String? content = 'cover-image',
  String? id = 'meta-1',
  String? refines = '#uid',
  String? property = 'dcterms:modified',
  String? scheme = 'marc:relators',
  Map<String, String>? attributes,
}) =>
    EpubMetadataMeta()
      ..Name = name
      ..Content = content
      ..Id = id
      ..Refines = refines
      ..Property = property
      ..Scheme = scheme
      ..Attributes = attributes;

/// Every list field assigned, which is what `EpubMetadata.hashCode` requires
/// (TC-OPF-2).
EpubMetadata seedMetadata() => EpubMetadata()
  ..Titles = <String>['NGE-SEED OPF Book']
  ..Creators = <EpubMetadataCreator>[seedCreator()]
  ..Subjects = <String>['NGE-SEED Subject']
  ..Description = 'NGE-SEED description'
  ..Publishers = <String>['NGE-SEED Press']
  ..Contributors = <EpubMetadataContributor>[seedContributor()]
  ..Dates = <EpubMetadataDate>[seedDate()]
  ..Types = <String>['NGE-SEED Type']
  ..Formats = <String>['application/epub+zip']
  ..Identifiers = <EpubMetadataIdentifier>[seedIdentifier()]
  ..Sources = <String>['NGE-SEED Source']
  ..Languages = <String>['en']
  ..Relations = <String>['NGE-SEED Relation']
  ..Coverages = <String>['NGE-SEED Coverage']
  ..Rights = <String>['NGE-SEED Rights']
  ..MetaItems = <EpubMetadataMeta>[seedMeta()];

EpubManifestItem seedManifestItem({
  String? id = 'ch1',
  String? href = 'chapter1.xhtml',
  String? mediaType = 'application/xhtml+xml',
  String? mediaOverlay = 'overlay-1',
  String? requiredNamespace = 'http://example.org/NGE-SEED',
  String? requiredModules = 'NGE-SEED-module',
  String? fallback = 'fallback-1',
  String? fallbackStyle = 'fallback-style-1',
  String? properties = 'nav',
}) =>
    EpubManifestItem()
      ..Id = id
      ..Href = href
      ..MediaType = mediaType
      ..MediaOverlay = mediaOverlay
      ..RequiredNamespace = requiredNamespace
      ..RequiredModules = requiredModules
      ..Fallback = fallback
      ..FallbackStyle = fallbackStyle
      ..Properties = properties;

EpubSpineItemRef seedSpineItemRef({
  String? idRef = 'ch1',
  bool? isLinear = true,
}) =>
    EpubSpineItemRef()
      ..IdRef = idRef
      ..IsLinear = isLinear;

EpubSpine seedSpine({
  String? tableOfContents = 'ncx',
  bool? ltr = true,
  List<EpubSpineItemRef>? items,
}) =>
    EpubSpine()
      ..TableOfContents = tableOfContents
      ..ltr = ltr
      ..Items = items ?? <EpubSpineItemRef>[seedSpineItemRef()];

EpubGuideReference seedGuideReference({
  String? type = 'cover',
  String? title = 'NGE-SEED Cover',
  String? href = 'cover.xhtml',
}) =>
    EpubGuideReference()
      ..Type = type
      ..Title = title
      ..Href = href;

EpubGuide seedGuide({List<EpubGuideReference>? items}) =>
    EpubGuide()..Items = items ?? <EpubGuideReference>[seedGuideReference()];

EpubManifest seedManifest({List<EpubManifestItem>? items}) =>
    EpubManifest()..Items = items ?? <EpubManifestItem>[seedManifestItem()];

EpubPackage seedPackage() => EpubPackage()
  ..Version = EpubVersion.Epub2
  ..Metadata = seedMetadata()
  ..Manifest = seedManifest()
  ..Spine = seedSpine()
  ..Guide = seedGuide();

/// An operand of an unrelated type, held as `Object` so each comparison below
/// is a real runtime check. Typing it `Object` rather than inlining a literal
/// is what keeps these tests free of an `unrelated_type_equality_checks`
/// suppression, which this package's lint forbids outright.
const Object unrelatedOperand = 'NGE-SEED-not-a-schema-object';

/// A null operand, typed nullable so the analyzer does not fold the comparison
/// away as a statically-known mismatch. Every class under test must answer
/// false here rather than throw.
const Object? nullOperand = null;

void main() {
  group('The OPF layer as a whole', () {
    // TC-OPF-1 [Error guessing]: the regression guard for a defect shared by
    // every class in this directory. `operator ==` used to open with
    // `other as X?`, so comparing against an unrelated type threw a
    // `TypeError` where the Dart contract requires `false` — only a null
    // operand was handled, because `as X?` admits null. Both operands now
    // answer false.
    for (final MapEntry<String, Object> row in <String, Object>{
      'EpubPackage': seedPackage(),
      'EpubMetadata': seedMetadata(),
      'EpubMetadataCreator': seedCreator(),
      'EpubMetadataContributor': seedContributor(),
      'EpubMetadataDate': seedDate(),
      'EpubMetadataIdentifier': seedIdentifier(),
      'EpubMetadataMeta': seedMeta(),
      'EpubManifest': seedManifest(),
      'EpubManifestItem': seedManifestItem(),
      'EpubSpine': seedSpine(),
      'EpubSpineItemRef': seedSpineItemRef(),
      'EpubGuide': seedGuide(),
      'EpubGuideReference': seedGuideReference(),
    }.entries) {
      test(
          'TC-OPF-1 [Error guessing]: ${row.key} == an unrelated type '
          'returns false', () {
        expect(row.value == unrelatedOperand, isFalse);
        expect(row.value == nullOperand, isFalse);
      });
    }

    // TC-OPF-2 [Error guessing]: KNOWN DEFECT. `EpubMetadata.hashCode` and
    // `EpubSpine.hashCode` dereference their list fields with `!`, and neither
    // class has a constructor that assigns them, so a bare instance cannot be
    // hashed. `PackageReader` always assigns them, which is why the read path
    // never hits this. Pinned as it behaves today.
    test(
        'TC-OPF-2 [Error guessing]: KNOWN DEFECT — a bare EpubMetadata or '
        'EpubSpine cannot be hashed', () {
      expect(() => EpubMetadata().hashCode, throwsA(isA<TypeError>()));
      expect(() => EpubSpine().hashCode, throwsA(isA<TypeError>()));
    });

    // TC-OPF-3 [Boundary value]: the classes that DO initialise their list in
    // a constructor hash fine when bare — the contrast that makes TC-OPF-2 a
    // missing constructor rather than an inherent trait of the layer.
    test('TC-OPF-3 [Boundary]: constructor-initialised classes hash when bare',
        () {
      expect(EpubGuide().Items, isEmpty);
      expect(EpubGuide().hashCode, isA<int>());
      expect(EpubManifest().Items, isEmpty);
      expect(EpubManifest().hashCode, isA<int>());
      expect(EpubPackage().hashCode, isA<int>());
      expect(EpubManifestItem().hashCode, isA<int>());
      expect(EpubMetadataMeta().hashCode, isA<int>());
      expect(EpubSpineItemRef().hashCode, isA<int>());
      expect(EpubGuideReference().hashCode, isA<int>());
      expect(EpubMetadataCreator().hashCode, isA<int>());
      expect(EpubMetadataContributor().hashCode, isA<int>());
      expect(EpubMetadataDate().hashCode, isA<int>());
      expect(EpubMetadataIdentifier().hashCode, isA<int>());
    });

    // TC-OPF-4 [Scenario/use-case]: every class agrees with its own twin, on
    // both `==` and `hashCode`.
    for (final MapEntry<String, List<Object>> row in <String, List<Object>>{
      'EpubPackage': <Object>[seedPackage(), seedPackage()],
      'EpubMetadata': <Object>[seedMetadata(), seedMetadata()],
      'EpubMetadataCreator': <Object>[seedCreator(), seedCreator()],
      'EpubMetadataContributor': <Object>[seedContributor(), seedContributor()],
      'EpubMetadataDate': <Object>[seedDate(), seedDate()],
      'EpubMetadataIdentifier': <Object>[seedIdentifier(), seedIdentifier()],
      'EpubMetadataMeta': <Object>[seedMeta(), seedMeta()],
      'EpubManifest': <Object>[seedManifest(), seedManifest()],
      'EpubManifestItem': <Object>[seedManifestItem(), seedManifestItem()],
      'EpubSpine': <Object>[seedSpine(), seedSpine()],
      'EpubSpineItemRef': <Object>[seedSpineItemRef(), seedSpineItemRef()],
      'EpubGuide': <Object>[seedGuide(), seedGuide()],
      'EpubGuideReference': <Object>[
        seedGuideReference(),
        seedGuideReference(),
      ],
    }.entries) {
      test('TC-OPF-4 [Scenario]: two identical ${row.key} values are equal',
          () {
        expect(row.value[0], equals(row.value[1]));
        expect(row.value[0].hashCode, equals(row.value[1].hashCode));
      });
    }
  });

  group('EpubMetadataCreator / EpubMetadataContributor', () {
    // TC-OPF-5 [Equivalence partitioning]: the two classes are structurally
    // identical, and each of their three fields decides equality once.
    for (final MapEntry<String, EpubMetadataCreator> row
        in <String, EpubMetadataCreator>{
      'Creator': seedCreator(creator: 'NGE-SEED Other'),
      'FileAs': seedCreator(fileAs: 'NGE-SEED Other'),
      'Role': seedCreator(role: 'ill'),
    }.entries) {
      test(
          'TC-OPF-5 [Equivalence partitioning]: a creator with a differing '
          '${row.key} is unequal', () {
        expect(seedCreator(), isNot(equals(row.value)));
        expect(seedCreator().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    for (final MapEntry<String, EpubMetadataContributor> row
        in <String, EpubMetadataContributor>{
      'Contributor': seedContributor(contributor: 'NGE-SEED Other'),
      'FileAs': seedContributor(fileAs: 'NGE-SEED Other'),
      'Role': seedContributor(role: 'ill'),
    }.entries) {
      test(
          'TC-OPF-5 [Equivalence partitioning]: a contributor with a '
          'differing ${row.key} is unequal', () {
        expect(seedContributor(), isNot(equals(row.value)));
        expect(seedContributor().hashCode, isNot(equals(row.value.hashCode)));
      });
    }
  });

  group('EpubMetadataDate / EpubMetadataIdentifier', () {
    // TC-OPF-6 [Equivalence partitioning]: both fields of a date decide.
    for (final MapEntry<String, EpubMetadataDate> row
        in <String, EpubMetadataDate>{
      'Date': seedDate(date: '1999-01-01'),
      'Event': seedDate(event: 'modification'),
    }.entries) {
      test(
          'TC-OPF-6 [Equivalence partitioning]: a date with a differing '
          '${row.key} is unequal', () {
        expect(seedDate(), isNot(equals(row.value)));
      });
    }

    // TC-OPF-7 [Equivalence partitioning]: all three fields of an identifier.
    for (final MapEntry<String, EpubMetadataIdentifier> row
        in <String, EpubMetadataIdentifier>{
      'Id': seedIdentifier(id: 'other-uid'),
      'Scheme': seedIdentifier(scheme: 'ISBN'),
      'Identifier': seedIdentifier(identifier: 'urn:uuid:NGE-SEED-OTHER'),
    }.entries) {
      test(
          'TC-OPF-7 [Equivalence partitioning]: an identifier with a '
          'differing ${row.key} is unequal', () {
        expect(seedIdentifier(), isNot(equals(row.value)));
      });
    }

    // TC-OPF-8 [Boundary value]: an all-null date still compares, and its
    // `hash2` is stable.
    test('TC-OPF-8 [Boundary]: all-null dates and identifiers are equal', () {
      expect(EpubMetadataDate(), equals(EpubMetadataDate()));
      expect(EpubMetadataIdentifier(), equals(EpubMetadataIdentifier()));
    });
  });

  group('EpubMetadataMeta', () {
    // TC-OPF-9 [Equivalence partitioning]: the six string fields each decide.
    for (final MapEntry<String, EpubMetadataMeta> row
        in <String, EpubMetadataMeta>{
      'Name': seedMeta(name: 'NGE-SEED-other'),
      'Content': seedMeta(content: 'NGE-SEED-other'),
      'Id': seedMeta(id: 'meta-2'),
      'Refines': seedMeta(refines: '#other'),
      'Property': seedMeta(property: 'dcterms:created'),
      'Scheme': seedMeta(scheme: 'onix:codelist17'),
    }.entries) {
      test(
          'TC-OPF-9 [Equivalence partitioning]: a meta with a differing '
          '${row.key} is unequal', () {
        expect(seedMeta(), isNot(equals(row.value)));
        expect(seedMeta().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-OPF-10 [Error guessing]: `Attributes` is declared on the class but
    // appears in neither `==` nor `hashCode`, so two metas that differ only in
    // their attribute bag compare EQUAL. That is deliberate enough to rely on
    // — the EPUB3 `<meta>` reader stores the raw attribute bag there for
    // callers, not for identity — but it is invisible from the class body, so
    // it is pinned here.
    test(
        'TC-OPF-10 [Error guessing]: Attributes takes no part in equality or '
        'hashCode', () {
      final EpubMetadataMeta withAttributes = seedMeta(
        attributes: <String, String>{'data-nge-seed': 'yes'},
      );
      final EpubMetadataMeta withoutAttributes = seedMeta();

      expect(withAttributes.Attributes, isNotNull);
      expect(withoutAttributes.Attributes, isNull);
      expect(withAttributes, equals(withoutAttributes));
      expect(withAttributes.hashCode, equals(withoutAttributes.hashCode));
    });
  });

  group('EpubMetadata', () {
    // TC-OPF-11 [Equivalence partitioning]: fifteen list fields plus
    // `Description`, each decisive on its own. `Description` is checked before
    // the lists, so it gets its own row at the head.
    test(
        'TC-OPF-11 [Equivalence partitioning]: a differing Description is '
        'unequal', () {
      final EpubMetadata other = seedMetadata()
        ..Description = 'NGE-SEED other description';

      expect(seedMetadata(), isNot(equals(other)));
    });

    for (final MapEntry<String, EpubMetadata Function(EpubMetadata)> row
        in <String, EpubMetadata Function(EpubMetadata)>{
      'Titles': (EpubMetadata m) => m..Titles = <String>['NGE-SEED Other'],
      'Creators': (EpubMetadata m) =>
          m..Creators = <EpubMetadataCreator>[seedCreator(creator: 'Other')],
      'Subjects': (EpubMetadata m) => m..Subjects = <String>['NGE-SEED Other'],
      'Publishers': (EpubMetadata m) =>
          m..Publishers = <String>['NGE-SEED Other'],
      'Contributors': (EpubMetadata m) => m
        ..Contributors = <EpubMetadataContributor>[
          seedContributor(contributor: 'Other'),
        ],
      'Dates': (EpubMetadata m) =>
          m..Dates = <EpubMetadataDate>[seedDate(date: '1999-01-01')],
      'Types': (EpubMetadata m) => m..Types = <String>['NGE-SEED Other'],
      'Formats': (EpubMetadata m) => m..Formats = <String>['NGE-SEED Other'],
      'Identifiers': (EpubMetadata m) => m
        ..Identifiers = <EpubMetadataIdentifier>[
          seedIdentifier(identifier: 'urn:uuid:NGE-SEED-OTHER'),
        ],
      'Sources': (EpubMetadata m) => m..Sources = <String>['NGE-SEED Other'],
      'Languages': (EpubMetadata m) => m..Languages = <String>['ja'],
      'Relations': (EpubMetadata m) =>
          m..Relations = <String>['NGE-SEED Other'],
      'Coverages': (EpubMetadata m) =>
          m..Coverages = <String>['NGE-SEED Other'],
      'Rights': (EpubMetadata m) => m..Rights = <String>['NGE-SEED Other'],
      'MetaItems': (EpubMetadata m) =>
          m..MetaItems = <EpubMetadataMeta>[seedMeta(name: 'other')],
    }.entries) {
      test(
          'TC-OPF-11 [Equivalence partitioning]: a differing ${row.key} is '
          'unequal', () {
        final EpubMetadata other = row.value(seedMetadata());

        expect(seedMetadata(), isNot(equals(other)));
        expect(seedMetadata().hashCode, isNot(equals(other.hashCode)));
      });
    }

    // TC-OPF-12 [Boundary value]: empty-but-assigned lists are the state the
    // reader produces for an OPF carrying only a title, and they hash.
    test('TC-OPF-12 [Boundary]: fully empty lists still hash and compare', () {
      EpubMetadata empty() => EpubMetadata()
        ..Titles = <String>[]
        ..Creators = <EpubMetadataCreator>[]
        ..Subjects = <String>[]
        ..Publishers = <String>[]
        ..Contributors = <EpubMetadataContributor>[]
        ..Dates = <EpubMetadataDate>[]
        ..Types = <String>[]
        ..Formats = <String>[]
        ..Identifiers = <EpubMetadataIdentifier>[]
        ..Sources = <String>[]
        ..Languages = <String>[]
        ..Relations = <String>[]
        ..Coverages = <String>[]
        ..Rights = <String>[]
        ..MetaItems = <EpubMetadataMeta>[];

      expect(empty(), equals(empty()));
      expect(empty().hashCode, equals(empty().hashCode));
      expect(empty(), isNot(equals(seedMetadata())));
    });
  });

  group('EpubManifest / EpubManifestItem', () {
    // TC-OPF-13 [Equivalence partitioning]: all nine manifest-item fields.
    for (final MapEntry<String, EpubManifestItem> row
        in <String, EpubManifestItem>{
      'Id': seedManifestItem(id: 'ch2'),
      'Href': seedManifestItem(href: 'chapter2.xhtml'),
      'MediaType': seedManifestItem(mediaType: 'text/css'),
      'MediaOverlay': seedManifestItem(mediaOverlay: 'overlay-2'),
      'RequiredNamespace': seedManifestItem(requiredNamespace: 'urn:other'),
      'RequiredModules': seedManifestItem(requiredModules: 'other-module'),
      'Fallback': seedManifestItem(fallback: 'fallback-2'),
      'FallbackStyle': seedManifestItem(fallbackStyle: 'fallback-style-2'),
      'Properties': seedManifestItem(properties: 'cover-image'),
    }.entries) {
      test(
          'TC-OPF-13 [Equivalence partitioning]: an item with a differing '
          '${row.key} is unequal', () {
        expect(seedManifestItem(), isNot(equals(row.value)));
        expect(seedManifestItem().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-OPF-14 [Scenario/use-case]: `toString` renders the five fields the
    // reader debug-prints.
    test(
        'TC-OPF-14 [Scenario]: toString renders id, href, type, properties '
        'and overlay', () {
      expect(
        seedManifestItem().toString(),
        'Id: ch1, Href = chapter1.xhtml, MediaType = application/xhtml+xml, '
        'Properties = nav, MediaOverlay = overlay-1',
      );
      expect(
        EpubManifestItem().toString(),
        'Id: null, Href = null, MediaType = null, Properties = null, '
        'MediaOverlay = null',
      );
    });

    // TC-OPF-15 [Equivalence partitioning]: the manifest compares its items
    // element-wise, so count and content both decide.
    test('TC-OPF-15 [Equivalence partitioning]: manifests differ by item list',
        () {
      expect(seedManifest(), isNot(equals(EpubManifest())));
      expect(
        seedManifest(),
        isNot(
          equals(
            seedManifest(
              items: <EpubManifestItem>[
                seedManifestItem(),
                seedManifestItem(id: 'ch2'),
              ],
            ),
          ),
        ),
      );
    });
  });

  group('EpubSpine / EpubSpineItemRef', () {
    // TC-OPF-16 [Equivalence partitioning]: both item-ref fields decide.
    for (final MapEntry<String, EpubSpineItemRef> row
        in <String, EpubSpineItemRef>{
      'IdRef': seedSpineItemRef(idRef: 'ch2'),
      'IsLinear': seedSpineItemRef(isLinear: false),
    }.entries) {
      test(
          'TC-OPF-16 [Equivalence partitioning]: a spine item with a '
          'differing ${row.key} is unequal', () {
        expect(seedSpineItemRef(), isNot(equals(row.value)));
        expect(seedSpineItemRef().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-OPF-17 [Scenario/use-case]: `toString` renders the idref only.
    test('TC-OPF-17 [Scenario]: a spine item ref renders its idref', () {
      expect(seedSpineItemRef().toString(), 'IdRef: ch1');
      expect(EpubSpineItemRef().toString(), 'IdRef: null');
    });

    // TC-OPF-18 [Equivalence partitioning]: the spine's three fields. `Items`
    // is checked first and short-circuits, so it is exercised on its own.
    for (final MapEntry<String, EpubSpine> row in <String, EpubSpine>{
      'Items': seedSpine(items: <EpubSpineItemRef>[]),
      'TableOfContents': seedSpine(tableOfContents: 'nav'),
      'ltr': seedSpine(ltr: false),
    }.entries) {
      test(
          'TC-OPF-18 [Equivalence partitioning]: a spine with a differing '
          '${row.key} is unequal', () {
        expect(seedSpine(), isNot(equals(row.value)));
        expect(seedSpine().hashCode, isNot(equals(row.value.hashCode)));
      });
    }

    // TC-OPF-19 [Boundary value]: `ltr` is a THREE-state field — null means
    // the OPF declared no page-progression-direction at all, which is not the
    // same as an explicit `ltr="false"`. `spine_direction_test.dart` pins how
    // the reader arrives at each; this pins that equality tells them apart.
    test('TC-OPF-19 [Boundary]: a null ltr differs from both true and false',
        () {
      expect(seedSpine(ltr: null), isNot(equals(seedSpine(ltr: true))));
      expect(seedSpine(ltr: null), isNot(equals(seedSpine(ltr: false))));
      expect(seedSpine(ltr: null), equals(seedSpine(ltr: null)));
    });
  });

  group('EpubGuide / EpubGuideReference', () {
    // TC-OPF-20 [Equivalence partitioning]: all three reference fields.
    for (final MapEntry<String, EpubGuideReference> row
        in <String, EpubGuideReference>{
      'Type': seedGuideReference(type: 'toc'),
      'Title': seedGuideReference(title: 'NGE-SEED Other'),
      'Href': seedGuideReference(href: 'toc.xhtml'),
    }.entries) {
      test(
          'TC-OPF-20 [Equivalence partitioning]: a guide reference with a '
          'differing ${row.key} is unequal', () {
        expect(seedGuideReference(), isNot(equals(row.value)));
      });
    }

    // TC-OPF-21 [Scenario/use-case]: `toString` renders type and href, and
    // notably NOT the title.
    test('TC-OPF-21 [Scenario]: a guide reference renders type and href', () {
      expect(seedGuideReference().toString(), 'Type: cover, Href: cover.xhtml');
      expect(EpubGuideReference().toString(), 'Type: null, Href: null');
    });

    // TC-OPF-22 [Boundary value]: an empty guide is the state the constructor
    // produces and what the reader leaves behind for an OPF with no `<guide>`.
    test('TC-OPF-22 [Boundary]: an empty guide differs from a populated one',
        () {
      expect(EpubGuide(), equals(EpubGuide()));
      expect(EpubGuide(), isNot(equals(seedGuide())));
      expect(EpubGuide().hashCode, isNot(equals(seedGuide().hashCode)));
    });
  });

  group('EpubPackage', () {
    // TC-OPF-23 [Equivalence partitioning]: all five fields decide.
    for (final MapEntry<String, EpubPackage Function(EpubPackage)> row
        in <String, EpubPackage Function(EpubPackage)>{
      'Version': (EpubPackage p) => p..Version = EpubVersion.Epub3,
      'Metadata': (EpubPackage p) =>
          p..Metadata = (seedMetadata()..Titles = <String>['NGE-SEED Other']),
      'Manifest': (EpubPackage p) => p..Manifest = EpubManifest(),
      'Spine': (EpubPackage p) => p..Spine = seedSpine(ltr: false),
      'Guide': (EpubPackage p) => p..Guide = EpubGuide(),
    }.entries) {
      test(
          'TC-OPF-23 [Equivalence partitioning]: a package with a differing '
          '${row.key} is unequal', () {
        final EpubPackage other = row.value(seedPackage());

        expect(seedPackage(), isNot(equals(other)));
        expect(seedPackage().hashCode, isNot(equals(other.hashCode)));
      });
    }

    // TC-OPF-24 [Boundary value]: an all-null package hashes and compares —
    // `EpubPackage` has no list fields, so it escapes TC-OPF-2.
    test('TC-OPF-24 [Boundary]: an all-null package is equal to another', () {
      expect(EpubPackage(), equals(EpubPackage()));
      expect(EpubPackage().hashCode, equals(EpubPackage().hashCode));
      expect(EpubPackage(), isNot(equals(seedPackage())));
    });

    // TC-OPF-25 [Boundary value]: the two enum values are distinguished.
    test('TC-OPF-25 [Boundary]: Epub2 and Epub3 packages are unequal', () {
      expect(
        EpubPackage()..Version = EpubVersion.Epub2,
        isNot(equals(EpubPackage()..Version = EpubVersion.Epub3)),
      );
      expect(EpubVersion.values, hasLength(2));
    });
  });
}
