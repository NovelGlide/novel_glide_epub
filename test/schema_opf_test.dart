// The OPF schema value types — `EpubPackage` and everything it holds:
// metadata and its six sub-types, manifest, spine, guide.
//
// These are immutable data holders, so they are exercised by direct
// construction; `package_reader_test.dart` covers how the reader fills them.
// Two traits run through the whole layer and are checked once each rather
// than per class:
//
//   * every `==` here answers false for an unrelated or a null operand
//     (TC-OPF-1), as the Dart equality contract requires.
//   * a field the OPF makes optional is nullable, and a null there is a value
//     of its own: it differs from any string on both `==` and `hashCode`
//     (TC-OPF-26).
//
// Every field of every class gets a one-field-at-a-time partition row that
// checks `==` AND `hashCode`, so dropping any clause of either is caught.
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_contributor.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_date.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_meta.dart';
import 'package:test/test.dart';

EpubMetadataCreator seedCreator({
  String creator = 'NGE-SEED Author',
  String? fileAs = 'Author, NGE-SEED',
  String? role = 'aut',
}) =>
    EpubMetadataCreator(creator: creator, fileAs: fileAs, role: role);

EpubMetadataContributor seedContributor({
  String contributor = 'NGE-SEED Contributor',
  String? fileAs = 'Contributor, NGE-SEED',
  String? role = 'edt',
}) =>
    EpubMetadataContributor(
      contributor: contributor,
      fileAs: fileAs,
      role: role,
    );

EpubMetadataDate seedDate({
  String date = '2026-09-21',
  String? event = 'publication',
}) =>
    EpubMetadataDate(date: date, event: event);

EpubMetadataIdentifier seedIdentifier({
  String? id = 'uid',
  String? scheme = 'URN',
  String identifier = 'urn:uuid:NGE-SEED-OPF',
}) =>
    EpubMetadataIdentifier(identifier: identifier, id: id, scheme: scheme);

EpubMetadataMeta seedMeta({
  String? name = 'cover',
  String content = 'cover-image',
  String? id = 'meta-1',
  String? refines = '#uid',
  String? property = 'dcterms:modified',
  String? scheme = 'marc:relators',
  Map<String, String> attributes = const <String, String>{},
}) =>
    EpubMetadataMeta(
      content: content,
      attributes: attributes,
      name: name,
      id: id,
      refines: refines,
      property: property,
      scheme: scheme,
    );

/// Every list field populated with one entry, so each can be made to differ
/// on its own by passing a replacement. The defaults are const literals, not
/// `?? fallback`s, so this helper carries no branch of its own.
EpubMetadata seedMetadata({
  List<String> titles = const <String>['NGE-SEED OPF Book'],
  List<EpubMetadataCreator> creators = const <EpubMetadataCreator>[
    EpubMetadataCreator(
      creator: 'NGE-SEED Author',
      fileAs: 'Author, NGE-SEED',
      role: 'aut',
    ),
  ],
  List<String> subjects = const <String>['NGE-SEED Subject'],
  List<String> descriptions = const <String>['NGE-SEED description'],
  List<String> publishers = const <String>['NGE-SEED Press'],
  List<EpubMetadataContributor> contributors = const <EpubMetadataContributor>[
    EpubMetadataContributor(
      contributor: 'NGE-SEED Contributor',
      fileAs: 'Contributor, NGE-SEED',
      role: 'edt',
    ),
  ],
  List<EpubMetadataDate> dates = const <EpubMetadataDate>[
    EpubMetadataDate(date: '2026-09-21', event: 'publication'),
  ],
  List<String> types = const <String>['NGE-SEED Type'],
  List<String> formats = const <String>['application/epub+zip'],
  List<EpubMetadataIdentifier> identifiers = const <EpubMetadataIdentifier>[
    EpubMetadataIdentifier(
      identifier: 'urn:uuid:NGE-SEED-OPF',
      id: 'uid',
      scheme: 'URN',
    ),
  ],
  List<String> sources = const <String>['NGE-SEED Source'],
  List<String> languages = const <String>['en'],
  List<String> relations = const <String>['NGE-SEED Relation'],
  List<String> coverages = const <String>['NGE-SEED Coverage'],
  List<String> rights = const <String>['NGE-SEED Rights'],
  List<EpubMetadataMeta> metaItems = const <EpubMetadataMeta>[
    EpubMetadataMeta(
      content: 'cover-image',
      name: 'cover',
      id: 'meta-1',
      refines: '#uid',
      property: 'dcterms:modified',
      scheme: 'marc:relators',
    ),
  ],
}) =>
    EpubMetadata(
      titles: titles,
      creators: creators,
      subjects: subjects,
      descriptions: descriptions,
      publishers: publishers,
      contributors: contributors,
      dates: dates,
      types: types,
      formats: formats,
      identifiers: identifiers,
      sources: sources,
      languages: languages,
      relations: relations,
      coverages: coverages,
      rights: rights,
      metaItems: metaItems,
    );

EpubManifestItem seedManifestItem({
  String id = 'ch1',
  String href = 'chapter1.xhtml',
  String mediaType = 'application/xhtml+xml',
  String? mediaOverlay = 'overlay-1',
  String? requiredNamespace = 'http://example.org/NGE-SEED',
  String? requiredModules = 'NGE-SEED-module',
  String? fallback = 'fallback-1',
  String? fallbackStyle = 'fallback-style-1',
  String? properties = 'nav',
}) =>
    EpubManifestItem(
      id: id,
      href: href,
      mediaType: mediaType,
      mediaOverlay: mediaOverlay,
      requiredNamespace: requiredNamespace,
      requiredModules: requiredModules,
      fallback: fallback,
      fallbackStyle: fallbackStyle,
      properties: properties,
    );

EpubSpineItemRef seedSpineItemRef({
  String idRef = 'ch1',
  bool isLinear = true,
}) =>
    EpubSpineItemRef(idRef: idRef, isLinear: isLinear);

EpubSpine seedSpine({
  String? tableOfContents = 'ncx',
  bool ltr = true,
  List<EpubSpineItemRef>? items,
}) =>
    EpubSpine(
      items: items ?? <EpubSpineItemRef>[seedSpineItemRef()],
      ltr: ltr,
      tableOfContents: tableOfContents,
    );

EpubGuideReference seedGuideReference({
  String type = 'cover',
  String? title = 'NGE-SEED Cover',
  String href = 'cover.xhtml',
}) =>
    EpubGuideReference(type: type, href: href, title: title);

EpubGuide seedGuide({List<EpubGuideReference>? items}) => EpubGuide(
      items: items ?? <EpubGuideReference>[seedGuideReference()],
    );

EpubManifest seedManifest({List<EpubManifestItem>? items}) => EpubManifest(
      items: items ?? <EpubManifestItem>[seedManifestItem()],
    );

/// A package with a guide. `guide` defaults to [seedGuide] only when the
/// caller passes nothing; [withoutGuide] builds the guide-less variant, since
/// an explicit null cannot be told apart from "not passed" here.
EpubPackage seedPackage({
  EpubVersion version = EpubVersion.epub2,
  EpubMetadata? metadata,
  EpubManifest? manifest,
  EpubSpine? spine,
  EpubGuide? guide,
  bool withoutGuide = false,
}) =>
    EpubPackage(
      version: version,
      metadata: metadata ?? seedMetadata(),
      manifest: manifest ?? seedManifest(),
      spine: spine ?? seedSpine(),
      guide: withoutGuide ? null : guide ?? seedGuide(),
    );

/// An operand of an unrelated type, held as `Object` so each comparison below
/// is a real runtime check. Typing it `Object` rather than inlining a literal
/// is what keeps these tests free of an `unrelated_type_equality_checks`
/// suppression, which this package's lint forbids outright.
const Object unrelatedOperand = 'NGE-SEED-not-a-schema-object';

/// A null operand, typed nullable so the analyzer does not fold the comparison
/// away as a statically-known mismatch. Every class under test must answer
/// false here rather than throw.
const Object? nullOperand = null;

/// Asserts that [a] and [b] differ on both `==` and `hashCode`: a partition
/// row that checked only `==` would let a field silently drop out of the hash.
void expectDistinct(Object a, Object b) {
  expect(a, isNot(equals(b)));
  expect(a.hashCode, isNot(equals(b.hashCode)));
}

void main() {
  group('The OPF layer as a whole', () {
    // TC-OPF-1 [Error guessing]: every `==` in this directory opens with an
    // `is` check, so an unrelated operand and a null one both answer false
    // rather than throw a `TypeError` — the Dart equality contract.
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

    // TC-OPF-3 [Boundary value]: an instance built from its required
    // arguments alone is what the reader produces for the sparsest legal
    // element. Its optional lists default to empty and its optional strings to
    // null, and it still hashes and compares.
    test(
        'TC-OPF-3 [Boundary]: required-only instances default their optional '
        'fields and still hash and compare', () {
      const EpubMetadata metadata = EpubMetadata(
        titles: <String>[],
        identifiers: <EpubMetadataIdentifier>[],
        languages: <String>[],
      );
      expect(metadata.creators, isEmpty);
      expect(metadata.metaItems, isEmpty);
      expect(metadata.descriptions, isEmpty);
      expect(metadata.hashCode, isA<int>());

      const EpubMetadataMeta meta = EpubMetadataMeta(content: '');
      expect(meta.attributes, isEmpty);
      expect(meta.name, isNull);
      expect(meta.property, isNull);

      const EpubPackage package = EpubPackage(
        version: EpubVersion.epub3,
        metadata: metadata,
        manifest: EpubManifest(items: <EpubManifestItem>[]),
        spine: EpubSpine(items: <EpubSpineItemRef>[], ltr: true),
      );
      expect(package.guide, isNull);
      expect(package.spine.tableOfContents, isNull);
      expect(package.hashCode, isA<int>());
      expect(package, isNot(equals(seedPackage())));
    });

    // TC-OPF-4 [Scenario/use-case]: every class agrees with its own twin, on
    // both `==` and `hashCode`. The twins are built separately, so neither
    // comparison can pass on identity alone.
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
        expect(identical(row.value[0], row.value[1]), isFalse);
        expect(row.value[0], equals(row.value[1]));
        expect(row.value[0].hashCode, equals(row.value[1].hashCode));
      });
    }

    // TC-OPF-26 [Boundary value]: each field the OPF makes optional is
    // nullable, and a null there is a distinct value — it equals another
    // null and differs from the populated field on `==` and `hashCode`.
    for (final MapEntry<String, List<Object>> row in <String, List<Object>>{
      'EpubGuideReference.title': <Object>[
        seedGuideReference(title: null),
        seedGuideReference(title: null),
        seedGuideReference(),
      ],
      'EpubSpine.tableOfContents': <Object>[
        seedSpine(tableOfContents: null),
        seedSpine(tableOfContents: null),
        seedSpine(),
      ],
      'EpubPackage.guide': <Object>[
        seedPackage(withoutGuide: true),
        seedPackage(withoutGuide: true),
        seedPackage(),
      ],
      'EpubMetadataMeta.name': <Object>[
        seedMeta(name: null),
        seedMeta(name: null),
        seedMeta(),
      ],
      'EpubMetadataMeta.id': <Object>[
        seedMeta(id: null),
        seedMeta(id: null),
        seedMeta(),
      ],
      'EpubMetadataMeta.refines': <Object>[
        seedMeta(refines: null),
        seedMeta(refines: null),
        seedMeta(),
      ],
      'EpubMetadataMeta.property': <Object>[
        seedMeta(property: null),
        seedMeta(property: null),
        seedMeta(),
      ],
      'EpubMetadataMeta.scheme': <Object>[
        seedMeta(scheme: null),
        seedMeta(scheme: null),
        seedMeta(),
      ],
      'EpubMetadataCreator.fileAs': <Object>[
        seedCreator(fileAs: null),
        seedCreator(fileAs: null),
        seedCreator(),
      ],
      'EpubMetadataCreator.role': <Object>[
        seedCreator(role: null),
        seedCreator(role: null),
        seedCreator(),
      ],
      'EpubMetadataContributor.fileAs': <Object>[
        seedContributor(fileAs: null),
        seedContributor(fileAs: null),
        seedContributor(),
      ],
      'EpubMetadataContributor.role': <Object>[
        seedContributor(role: null),
        seedContributor(role: null),
        seedContributor(),
      ],
      'EpubMetadataDate.event': <Object>[
        seedDate(event: null),
        seedDate(event: null),
        seedDate(),
      ],
      'EpubMetadataIdentifier.id': <Object>[
        seedIdentifier(id: null),
        seedIdentifier(id: null),
        seedIdentifier(),
      ],
      'EpubMetadataIdentifier.scheme': <Object>[
        seedIdentifier(scheme: null),
        seedIdentifier(scheme: null),
        seedIdentifier(),
      ],
      'EpubManifestItem.mediaOverlay': <Object>[
        seedManifestItem(mediaOverlay: null),
        seedManifestItem(mediaOverlay: null),
        seedManifestItem(),
      ],
      'EpubManifestItem.requiredNamespace': <Object>[
        seedManifestItem(requiredNamespace: null),
        seedManifestItem(requiredNamespace: null),
        seedManifestItem(),
      ],
      'EpubManifestItem.requiredModules': <Object>[
        seedManifestItem(requiredModules: null),
        seedManifestItem(requiredModules: null),
        seedManifestItem(),
      ],
      'EpubManifestItem.fallback': <Object>[
        seedManifestItem(fallback: null),
        seedManifestItem(fallback: null),
        seedManifestItem(),
      ],
      'EpubManifestItem.fallbackStyle': <Object>[
        seedManifestItem(fallbackStyle: null),
        seedManifestItem(fallbackStyle: null),
        seedManifestItem(),
      ],
      'EpubManifestItem.properties': <Object>[
        seedManifestItem(properties: null),
        seedManifestItem(properties: null),
        seedManifestItem(),
      ],
    }.entries) {
      test(
          'TC-OPF-26 [Boundary]: a null ${row.key} equals another null and '
          'differs from a value', () {
        expect(row.value[0], equals(row.value[1]));
        expect(row.value[0].hashCode, equals(row.value[1].hashCode));
        expectDistinct(row.value[0], row.value[2]);
      });
    }
  });

  group('EpubMetadataCreator / EpubMetadataContributor', () {
    // TC-OPF-5 [Equivalence partitioning]: the two classes are structurally
    // identical, and each of their three fields decides equality once.
    for (final MapEntry<String, EpubMetadataCreator> row
        in <String, EpubMetadataCreator>{
      'creator': seedCreator(creator: 'NGE-SEED Other'),
      'fileAs': seedCreator(fileAs: 'NGE-SEED Other'),
      'role': seedCreator(role: 'ill'),
    }.entries) {
      test(
          'TC-OPF-5 [Equivalence partitioning]: a creator with a differing '
          '${row.key} is unequal', () {
        expectDistinct(seedCreator(), row.value);
      });
    }

    for (final MapEntry<String, EpubMetadataContributor> row
        in <String, EpubMetadataContributor>{
      'contributor': seedContributor(contributor: 'NGE-SEED Other'),
      'fileAs': seedContributor(fileAs: 'NGE-SEED Other'),
      'role': seedContributor(role: 'ill'),
    }.entries) {
      test(
          'TC-OPF-5 [Equivalence partitioning]: a contributor with a '
          'differing ${row.key} is unequal', () {
        expectDistinct(seedContributor(), row.value);
      });
    }
  });

  group('EpubMetadataDate / EpubMetadataIdentifier', () {
    // TC-OPF-6 [Equivalence partitioning]: both fields of a date decide.
    for (final MapEntry<String, EpubMetadataDate> row
        in <String, EpubMetadataDate>{
      'date': seedDate(date: '1999-01-01'),
      'event': seedDate(event: 'modification'),
    }.entries) {
      test(
          'TC-OPF-6 [Equivalence partitioning]: a date with a differing '
          '${row.key} is unequal', () {
        expectDistinct(seedDate(), row.value);
      });
    }

    // TC-OPF-7 [Equivalence partitioning]: all three fields of an identifier.
    for (final MapEntry<String, EpubMetadataIdentifier> row
        in <String, EpubMetadataIdentifier>{
      'id': seedIdentifier(id: 'other-uid'),
      'scheme': seedIdentifier(scheme: 'ISBN'),
      'identifier': seedIdentifier(identifier: 'urn:uuid:NGE-SEED-OTHER'),
    }.entries) {
      test(
          'TC-OPF-7 [Equivalence partitioning]: an identifier with a '
          'differing ${row.key} is unequal', () {
        expectDistinct(seedIdentifier(), row.value);
      });
    }

    // TC-OPF-8 [Boundary value]: an empty element reads as empty text with no
    // attributes; two such dates, and two such identifiers, are equal.
    test('TC-OPF-8 [Boundary]: empty dates and identifiers are equal', () {
      expect(
        seedDate(date: '', event: null),
        equals(seedDate(date: '', event: null)),
      );
      expect(
        seedIdentifier(identifier: '', id: null, scheme: null),
        equals(seedIdentifier(identifier: '', id: null, scheme: null)),
      );
    });
  });

  group('EpubMetadataMeta', () {
    // TC-OPF-9 [Equivalence partitioning]: the six string fields each decide.
    for (final MapEntry<String, EpubMetadataMeta> row
        in <String, EpubMetadataMeta>{
      'name': seedMeta(name: 'NGE-SEED-other'),
      'content': seedMeta(content: 'NGE-SEED-other'),
      'id': seedMeta(id: 'meta-2'),
      'refines': seedMeta(refines: '#other'),
      'property': seedMeta(property: 'dcterms:created'),
      'scheme': seedMeta(scheme: 'onix:codelist17'),
    }.entries) {
      test(
          'TC-OPF-9 [Equivalence partitioning]: a meta with a differing '
          '${row.key} is unequal', () {
        expectDistinct(seedMeta(), row.value);
      });
    }

    // TC-OPF-10 [Error guessing]: `attributes` appears in neither `==` nor
    // `hashCode`, so two metas that differ only in their attribute bag compare
    // EQUAL. The bag is a raw view of the element for callers — it duplicates
    // the named fields and carries whatever else the element had — not part of
    // the meta's identity. Nothing in the class body says so, so it is pinned.
    test(
        'TC-OPF-10 [Error guessing]: attributes takes no part in equality or '
        'hashCode', () {
      final EpubMetadataMeta withAttributes = seedMeta(
        attributes: <String, String>{'data-nge-seed': 'yes'},
      );
      final EpubMetadataMeta otherAttributes = seedMeta(
        attributes: <String, String>{'data-nge-seed': 'no', 'lang': 'en'},
      );
      final EpubMetadataMeta withoutAttributes = seedMeta();

      expect(
          withAttributes.attributes, <String, String>{'data-nge-seed': 'yes'});
      expect(withoutAttributes.attributes, isEmpty);
      expect(withAttributes, equals(withoutAttributes));
      expect(withAttributes.hashCode, equals(withoutAttributes.hashCode));
      expect(withAttributes, equals(otherAttributes));
      expect(withAttributes.hashCode, equals(otherAttributes.hashCode));
    });
  });

  group('EpubMetadata', () {
    // TC-OPF-11 [Equivalence partitioning]: the fifteen Dublin Core lists and
    // `metaItems`, each decisive on its own. `==` compares them in several
    // groups, so every one gets a row of its own.
    for (final MapEntry<String, EpubMetadata> row in <String, EpubMetadata>{
      'descriptions':
          seedMetadata(descriptions: <String>['NGE-SEED other description']),
      'titles': seedMetadata(titles: <String>['NGE-SEED Other']),
      'creators': seedMetadata(
        creators: <EpubMetadataCreator>[seedCreator(creator: 'Other')],
      ),
      'subjects': seedMetadata(subjects: <String>['NGE-SEED Other']),
      'publishers': seedMetadata(publishers: <String>['NGE-SEED Other']),
      'contributors': seedMetadata(
        contributors: <EpubMetadataContributor>[
          seedContributor(contributor: 'Other'),
        ],
      ),
      'dates': seedMetadata(
        dates: <EpubMetadataDate>[seedDate(date: '1999-01-01')],
      ),
      'types': seedMetadata(types: <String>['NGE-SEED Other']),
      'formats': seedMetadata(formats: <String>['NGE-SEED Other']),
      'identifiers': seedMetadata(
        identifiers: <EpubMetadataIdentifier>[
          seedIdentifier(identifier: 'urn:uuid:NGE-SEED-OTHER'),
        ],
      ),
      'sources': seedMetadata(sources: <String>['NGE-SEED Other']),
      'languages': seedMetadata(languages: <String>['ja']),
      'relations': seedMetadata(relations: <String>['NGE-SEED Other']),
      'coverages': seedMetadata(coverages: <String>['NGE-SEED Other']),
      'rights': seedMetadata(rights: <String>['NGE-SEED Other']),
      'metaItems': seedMetadata(
        metaItems: <EpubMetadataMeta>[seedMeta(name: 'other')],
      ),
    }.entries) {
      test(
          'TC-OPF-11 [Equivalence partitioning]: a differing ${row.key} is '
          'unequal', () {
        expectDistinct(seedMetadata(), row.value);
      });
    }

    // TC-OPF-12 [Boundary value]: all-empty lists are the state the reader
    // produces for an OPF whose `<metadata>` is empty, and they hash.
    test('TC-OPF-12 [Boundary]: fully empty lists still hash and compare', () {
      EpubMetadata empty() => seedMetadata(
            titles: <String>[],
            creators: <EpubMetadataCreator>[],
            subjects: <String>[],
            descriptions: <String>[],
            publishers: <String>[],
            contributors: <EpubMetadataContributor>[],
            dates: <EpubMetadataDate>[],
            types: <String>[],
            formats: <String>[],
            identifiers: <EpubMetadataIdentifier>[],
            sources: <String>[],
            languages: <String>[],
            relations: <String>[],
            coverages: <String>[],
            rights: <String>[],
            metaItems: <EpubMetadataMeta>[],
          );

      expect(empty(), equals(empty()));
      expect(empty().hashCode, equals(empty().hashCode));
      expectDistinct(empty(), seedMetadata());
    });
  });

  group('EpubManifest / EpubManifestItem', () {
    // TC-OPF-13 [Equivalence partitioning]: all nine manifest-item fields.
    for (final MapEntry<String, EpubManifestItem> row
        in <String, EpubManifestItem>{
      'id': seedManifestItem(id: 'ch2'),
      'href': seedManifestItem(href: 'chapter2.xhtml'),
      'mediaType': seedManifestItem(mediaType: 'text/css'),
      'mediaOverlay': seedManifestItem(mediaOverlay: 'overlay-2'),
      'requiredNamespace': seedManifestItem(requiredNamespace: 'urn:other'),
      'requiredModules': seedManifestItem(requiredModules: 'other-module'),
      'fallback': seedManifestItem(fallback: 'fallback-2'),
      'fallbackStyle': seedManifestItem(fallbackStyle: 'fallback-style-2'),
      'properties': seedManifestItem(properties: 'cover-image'),
    }.entries) {
      test(
          'TC-OPF-13 [Equivalence partitioning]: an item with a differing '
          '${row.key} is unequal', () {
        expectDistinct(seedManifestItem(), row.value);
      });
    }

    // TC-OPF-14 [Scenario/use-case]: `toString` renders the five fields the
    // reader debug-prints, the two optional ones as `null` when absent.
    test(
        'TC-OPF-14 [Scenario]: toString renders id, href, type, properties '
        'and overlay', () {
      expect(
        seedManifestItem().toString(),
        'Id: ch1, Href = chapter1.xhtml, MediaType = application/xhtml+xml, '
        'Properties = nav, MediaOverlay = overlay-1',
      );
      expect(
        const EpubManifestItem(id: '', href: '', mediaType: '').toString(),
        'Id: , Href = , MediaType = , Properties = null, MediaOverlay = null',
      );
    });

    // TC-OPF-15 [Equivalence partitioning]: the manifest compares its items
    // element-wise, so count and content both decide.
    test('TC-OPF-15 [Equivalence partitioning]: manifests differ by item list',
        () {
      expectDistinct(
        seedManifest(),
        seedManifest(items: <EpubManifestItem>[]),
      );
      expectDistinct(
        seedManifest(),
        seedManifest(
          items: <EpubManifestItem>[
            seedManifestItem(),
            seedManifestItem(id: 'ch2'),
          ],
        ),
      );
      expectDistinct(
        seedManifest(),
        seedManifest(items: <EpubManifestItem>[seedManifestItem(id: 'ch2')]),
      );
    });
  });

  group('EpubSpine / EpubSpineItemRef', () {
    // TC-OPF-16 [Equivalence partitioning]: both item-ref fields decide.
    for (final MapEntry<String, EpubSpineItemRef> row
        in <String, EpubSpineItemRef>{
      'idRef': seedSpineItemRef(idRef: 'ch2'),
      'isLinear': seedSpineItemRef(isLinear: false),
    }.entries) {
      test(
          'TC-OPF-16 [Equivalence partitioning]: a spine item with a '
          'differing ${row.key} is unequal', () {
        expectDistinct(seedSpineItemRef(), row.value);
      });
    }

    // TC-OPF-17 [Scenario/use-case]: `toString` renders the idref only, an
    // empty one included.
    test('TC-OPF-17 [Scenario]: a spine item ref renders its idref', () {
      expect(seedSpineItemRef().toString(), 'IdRef: ch1');
      expect(seedSpineItemRef(idRef: '').toString(), 'IdRef: ');
    });

    // TC-OPF-18 [Equivalence partitioning]: the spine's three fields. `items`
    // is checked first and short-circuits, so it is exercised on its own.
    for (final MapEntry<String, EpubSpine> row in <String, EpubSpine>{
      'items': seedSpine(items: <EpubSpineItemRef>[]),
      'tableOfContents': seedSpine(tableOfContents: 'nav'),
      'ltr': seedSpine(ltr: false),
    }.entries) {
      test(
          'TC-OPF-18 [Equivalence partitioning]: a spine with a differing '
          '${row.key} is unequal', () {
        expectDistinct(seedSpine(), row.value);
      });
    }
  });

  group('EpubGuide / EpubGuideReference', () {
    // TC-OPF-20 [Equivalence partitioning]: all three reference fields.
    for (final MapEntry<String, EpubGuideReference> row
        in <String, EpubGuideReference>{
      'type': seedGuideReference(type: 'toc'),
      'title': seedGuideReference(title: 'NGE-SEED Other'),
      'href': seedGuideReference(href: 'toc.xhtml'),
    }.entries) {
      test(
          'TC-OPF-20 [Equivalence partitioning]: a guide reference with a '
          'differing ${row.key} is unequal', () {
        expectDistinct(seedGuideReference(), row.value);
      });
    }

    // TC-OPF-21 [Scenario/use-case]: `toString` renders type and href, and
    // notably NOT the title — a titled and an untitled reference print alike.
    test('TC-OPF-21 [Scenario]: a guide reference renders type and href', () {
      expect(seedGuideReference().toString(), 'Type: cover, Href: cover.xhtml');
      expect(
        seedGuideReference(title: null).toString(),
        'Type: cover, Href: cover.xhtml',
      );
    });

    // TC-OPF-22 [Boundary value]: a guide with no reference is what the reader
    // produces for an empty `<guide>`; it differs from a populated one, and
    // the guide compares its references element-wise.
    test('TC-OPF-22 [Boundary]: an empty guide differs from a populated one',
        () {
      expect(
        seedGuide(items: <EpubGuideReference>[]),
        equals(seedGuide(items: <EpubGuideReference>[])),
      );
      expectDistinct(seedGuide(items: <EpubGuideReference>[]), seedGuide());
      expectDistinct(
        seedGuide(),
        seedGuide(items: <EpubGuideReference>[seedGuideReference(type: 'toc')]),
      );
    });
  });

  group('EpubPackage', () {
    // TC-OPF-23 [Equivalence partitioning]: all five fields decide.
    for (final MapEntry<String, EpubPackage> row in <String, EpubPackage>{
      'version': seedPackage(version: EpubVersion.epub3),
      'metadata': seedPackage(
        metadata: seedMetadata(titles: <String>['NGE-SEED Other']),
      ),
      'manifest': seedPackage(
        manifest: seedManifest(items: <EpubManifestItem>[]),
      ),
      'spine': seedPackage(spine: seedSpine(ltr: false)),
      'guide': seedPackage(guide: seedGuide(items: <EpubGuideReference>[])),
    }.entries) {
      test(
          'TC-OPF-23 [Equivalence partitioning]: a package with a differing '
          '${row.key} is unequal', () {
        expectDistinct(seedPackage(), row.value);
      });
    }

    // TC-OPF-25 [Boundary value]: the two enum values are distinguished.
    test('TC-OPF-25 [Boundary]: epub2 and epub3 packages are unequal', () {
      expect(
        seedPackage(),
        isNot(equals(seedPackage(version: EpubVersion.epub3))),
      );
      expect(EpubVersion.values, hasLength(2));
    });
  });
}
