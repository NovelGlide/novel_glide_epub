// `PackageReader` — the OPF reader — element by element.
//
// `spine_direction_test.dart` already pins the page-progression-direction
// rule; this file covers the rest: guide, manifest, the Dublin Core metadata
// walk, both `<meta>` dialects, and the whole-package assembly with its
// archive-level guards.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/readers/package_reader.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_date.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_meta.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/epub_fixture.dart';

XmlElement _element(String xml) => XmlDocument.parse(xml).rootElement;

Matcher _throwsMessageContaining(String fragment) => throwsA(
      isA<Exception>().having(
        (Exception e) => e.toString(),
        'message',
        contains(fragment),
      ),
    );

void main() {
  group('PackageReader.readGuide', () {
    // TC-PKG-1 [Scenario/use-case]: every guide reference attribute is read,
    // and non-`reference` children are skipped.
    test(
        'TC-PKG-1 [Scenario]: reads type/title/href and skips foreign '
        'children', () {
      final EpubGuide guide = const PackageReader().readGuide(
        _element('<guide>'
            '<notAReference type="x" href="y"/>'
            '<reference type="cover" title="NGE-SEED Cover" '
            'href="cover.xhtml"/>'
            '</guide>'),
      );

      expect(guide.items, hasLength(1));
      expect(guide.items.single.type, 'cover');
      expect(guide.items.single.title, 'NGE-SEED Cover');
      expect(guide.items.single.href, 'cover.xhtml');
    });

    // TC-PKG-2 [Boundary value]: type and href are each required, absent or
    // empty.
    for (final List<String> row in <List<String>>[
      <String>['<reference href="cover.xhtml"/>', 'item type is missing'],
      <String>[
        '<reference type="" href="cover.xhtml"/>',
        'item type is missing',
      ],
      <String>['<reference type="cover"/>', 'item href is missing'],
      <String>['<reference type="cover" href=""/>', 'item href is missing'],
    ]) {
      test('TC-PKG-2 [Boundary]: guide reference ${row[0]} is rejected', () {
        expect(
          () => const PackageReader()
              .readGuide(_element('<guide>${row[0]}</guide>')),
          _throwsMessageContaining(row[1]),
        );
      });
    }

    // TC-PKG-24 [Boundary value]: OPF 2 makes a reference's `title`
    // optional, so its absence reads null rather than '' or a rejection.
    // Attributes match by lower-cased local name, as they do everywhere.
    test(
        'TC-PKG-24 [Boundary]: a guide reference without a title reads a '
        'null title', () {
      final EpubGuide guide = const PackageReader().readGuide(
        _element('<guide>'
            '<reference TYPE="toc" HREF="toc.xhtml"/>'
            '<Reference type="text" href="ch1.xhtml" Title="NGE-SEED Start"/>'
            '</guide>'),
      );

      expect(guide.items, hasLength(2));
      expect(guide.items[0].type, 'toc');
      expect(guide.items[0].href, 'toc.xhtml');
      expect(guide.items[0].title, isNull);
      expect(guide.items[1].title, 'NGE-SEED Start');
    });

    // TC-PKG-25 [Boundary value]: a guide with no reference reads an empty
    // list.
    test('TC-PKG-25 [Boundary]: an empty guide reads no items', () {
      expect(
          const PackageReader().readGuide(_element('<guide/>')).items, isEmpty);
    });
  });

  group('PackageReader.readManifest', () {
    // TC-PKG-3 [Scenario/use-case]: every manifest item attribute the parser
    // knows is mapped onto the entity.
    test('TC-PKG-3 [Scenario]: reads every known manifest item attribute', () {
      final EpubManifest manifest = const PackageReader().readManifest(
        _element('<manifest>'
            '<notAnItem id="ignored"/>'
            '<item id="ch1" href="chapter1.xhtml" '
            'media-type="application/xhtml+xml" media-overlay="ov1" '
            'required-namespace="ns" required-modules="mods" '
            'fallback="ch2" fallback-style="style1" properties="nav"/>'
            '</manifest>'),
      );

      expect(manifest.items, hasLength(1));
      final EpubManifestItem item = manifest.items.single;
      expect(item.id, 'ch1');
      expect(item.href, 'chapter1.xhtml');
      expect(item.mediaType, 'application/xhtml+xml');
      expect(item.mediaOverlay, 'ov1');
      expect(item.requiredNamespace, 'ns');
      expect(item.requiredModules, 'mods');
      expect(item.fallback, 'ch2');
      expect(item.fallbackStyle, 'style1');
      expect(item.properties, 'nav');
    });

    // TC-PKG-4 [Boundary value]: id, href and media-type are each required,
    // absent or empty.
    for (final List<String> row in <List<String>>[
      <String>[
        '<item href="c.xhtml" media-type="application/xhtml+xml"/>',
        'item ID is missing',
      ],
      <String>[
        '<item id="" href="c.xhtml" media-type="application/xhtml+xml"/>',
        'item ID is missing',
      ],
      <String>[
        '<item id="ch1" media-type="application/xhtml+xml"/>',
        'item href is missing',
      ],
      <String>[
        '<item id="ch1" href="" media-type="application/xhtml+xml"/>',
        'item href is missing',
      ],
      <String>['<item id="ch1" href="c.xhtml"/>', 'item media type is missing'],
      <String>[
        '<item id="ch1" href="c.xhtml" media-type=""/>',
        'item media type is missing',
      ],
    ]) {
      test('TC-PKG-4 [Boundary]: manifest item ${row[0]} is rejected', () {
        expect(
          () => const PackageReader().readManifest(
            _element('<manifest>${row[0]}</manifest>'),
          ),
          _throwsMessageContaining(row[1]),
        );
      });
    }

    // TC-PKG-26 [Boundary value]: an item carrying only the three required
    // attributes reads every optional one as null, and items keep manifest
    // order. The href is kept exactly as written — decoding it is the content
    // map's job, not the package reader's.
    test(
        'TC-PKG-26 [Boundary]: optional manifest item attributes read null, '
        'and the href is kept as written', () {
      final EpubManifest manifest = const PackageReader().readManifest(
        _element('<manifest xmlns:opf="http://www.idpf.org/2007/opf">'
            '<item id="b" href="%E7%AC%AC.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<ITEM opf:ID="a" HREF="a.css" Media-Type="text/css"/>'
            '</manifest>'),
      );

      expect(
        manifest.items.map((EpubManifestItem item) => item.id),
        <String>['b', 'a'],
      );
      final EpubManifestItem item = manifest.items.first;
      expect(item.href, '%E7%AC%AC.xhtml');
      expect(item.mediaOverlay, isNull);
      expect(item.requiredNamespace, isNull);
      expect(item.requiredModules, isNull);
      expect(item.fallback, isNull);
      expect(item.fallbackStyle, isNull);
      expect(item.properties, isNull);
      expect(manifest.items.last.href, 'a.css');
      expect(manifest.items.last.mediaType, 'text/css');
    });
  });

  group('PackageReader.readMetadata', () {
    const String everyDublinCoreElement = '<metadata>'
        '<title>NGE-SEED Title</title>'
        '<creator role="aut" file-as="Seed, A">NGE-SEED Creator</creator>'
        '<subject>NGE-SEED Subject</subject>'
        '<description>NGE-SEED Description</description>'
        '<publisher>NGE-SEED Publisher</publisher>'
        '<contributor role="trl" file-as="Seed, B">NGE-SEED Contributor'
        '</contributor>'
        '<date event="publication">2026-09-21</date>'
        '<type>NGE-SEED Type</type>'
        '<format>application/epub+zip</format>'
        '<identifier id="uid" scheme="URN">urn:uuid:NGE-SEED</identifier>'
        '<source>NGE-SEED Source</source>'
        '<language>en</language>'
        '<relation>NGE-SEED Relation</relation>'
        '<coverage>NGE-SEED Coverage</coverage>'
        '<rights>NGE-SEED Rights</rights>'
        '<unknownElement>ignored</unknownElement>'
        '</metadata>';

    // TC-PKG-5 [Scenario/use-case]: one metadata block containing every
    // Dublin Core element the reader handles lands in the matching list, and
    // an unknown element is ignored rather than failing the parse.
    test('TC-PKG-5 [Scenario]: every Dublin Core element lands in its list',
        () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element(everyDublinCoreElement),
        EpubVersion.epub2,
      );

      expect(metadata.titles, <String>['NGE-SEED Title']);
      expect(metadata.subjects, <String>['NGE-SEED Subject']);
      expect(metadata.descriptions, <String>['NGE-SEED Description']);
      expect(metadata.publishers, <String>['NGE-SEED Publisher']);
      expect(metadata.types, <String>['NGE-SEED Type']);
      expect(metadata.formats, <String>['application/epub+zip']);
      expect(metadata.sources, <String>['NGE-SEED Source']);
      expect(metadata.languages, <String>['en']);
      expect(metadata.relations, <String>['NGE-SEED Relation']);
      expect(metadata.coverages, <String>['NGE-SEED Coverage']);
      expect(metadata.rights, <String>['NGE-SEED Rights']);
    });

    // TC-PKG-6 [Scenario/use-case]: the structured elements keep their
    // attributes, not just their text.
    test(
        'TC-PKG-6 [Scenario]: creator, contributor, date and identifier keep '
        'their attributes', () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element(everyDublinCoreElement),
        EpubVersion.epub2,
      );

      expect(metadata.creators.single.creator, 'NGE-SEED Creator');
      expect(metadata.creators.single.role, 'aut');
      expect(metadata.creators.single.fileAs, 'Seed, A');
      expect(metadata.contributors.single.contributor, 'NGE-SEED Contributor');
      expect(metadata.contributors.single.role, 'trl');
      expect(metadata.contributors.single.fileAs, 'Seed, B');
      expect(metadata.dates.single.date, '2026-09-21');
      expect(metadata.dates.single.event, 'publication');
      expect(metadata.identifiers.single.identifier, 'urn:uuid:NGE-SEED');
      expect(metadata.identifiers.single.id, 'uid');
      expect(metadata.identifiers.single.scheme, 'URN');
    });

    // TC-PKG-7 [Boundary value]: a date with an empty event attribute leaves
    // event null — the other side of the non-empty check.
    test(
        'TC-PKG-7 [Boundary]: a date with an empty event attribute leaves '
        'Event null', () {
      final EpubMetadataDate date = const PackageReader().readMetadataDate(
        _element('<date event="">2026-09-21</date>'),
      );

      expect(date.event, isNull);
      expect(date.date, '2026-09-21');
    });

    // TC-PKG-8 [Equivalence partitioning]: `<meta>` is version-dependent —
    // EPUB2 reads name/content attributes, EPUB3 reads the property dialect
    // plus element text. Each version fills only its own fields; every
    // attribute stays readable through `attributes` either way.
    test(
        'TC-PKG-8 [Equivalence partitioning]: EPUB2 meta reads name and '
        'content attributes', () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element('<metadata>'
            '<meta name="cover" content="cover-img" id="m1" '
            'property="NGE-SEED-EPUB3-only">NGE-SEED text</meta>'
            '</metadata>'),
        EpubVersion.epub2,
      );

      final EpubMetadataMeta meta = metadata.metaItems.single;
      expect(meta.name, 'cover');
      // The attribute, not the element text: an EPUB2 meta is empty.
      expect(meta.content, 'cover-img');
      // The EPUB3 fields stay null in an EPUB2 book even when the attribute
      // is there; it is still reachable through `attributes`.
      expect(meta.id, isNull);
      expect(meta.property, isNull);
      expect(meta.refines, isNull);
      expect(meta.scheme, isNull);
      expect(meta.attributes, <String, String>{
        'name': 'cover',
        'content': 'cover-img',
        'id': 'm1',
        'property': 'NGE-SEED-EPUB3-only',
      });
    });

    test(
        'TC-PKG-9 [Equivalence partitioning]: EPUB3 meta reads the property '
        'dialect and the element text', () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element('<metadata>'
            '<meta id="m1" refines="#uid" property="identifier-type" '
            'scheme="onix:codelist5" name="NGE-SEED-EPUB2-only" '
            'content="NGE-SEED-attribute">15</meta>'
            '</metadata>'),
        EpubVersion.epub3,
      );

      final EpubMetadataMeta meta = metadata.metaItems.single;
      expect(meta.id, 'm1');
      expect(meta.refines, '#uid');
      expect(meta.property, 'identifier-type');
      expect(meta.scheme, 'onix:codelist5');
      // The element text, not the `content` attribute.
      expect(meta.content, '15');
      expect(meta.name, isNull);
      expect(meta.attributes, <String, String>{
        'id': 'm1',
        'refines': '#uid',
        'property': 'identifier-type',
        'scheme': 'onix:codelist5',
        'name': 'NGE-SEED-EPUB2-only',
        'content': 'NGE-SEED-attribute',
      });
    });

    // TC-PKG-19 [Boundary value]: EPUB2 requires `content` on a meta, but a
    // book that leaves it out still opens — content reads '' rather than
    // failing the parse — while `name`, which the spec makes optional, reads
    // null when absent. Attributes match by lower-cased local name, so
    // `NAME` and `opf:content` are read too.
    test(
        'TC-PKG-19 [Boundary]: an EPUB2 meta without content reads it as '
        'empty, without name as null', () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element('<metadata xmlns:opf="http://www.idpf.org/2007/opf">'
            '<meta NAME="calibre:series"/>'
            '<meta scheme="NGE-SEED"/>'
            '<meta opf:content="NGE-SEED-prefixed"/>'
            '</metadata>'),
        EpubVersion.epub2,
      );

      final List<EpubMetadataMeta> metas = metadata.metaItems;
      expect(metas, hasLength(3));
      expect(metas[0].name, 'calibre:series');
      expect(metas[0].content, '');
      expect(metas[0].attributes, <String, String>{'name': 'calibre:series'});
      expect(metas[1].name, isNull);
      expect(metas[1].content, '');
      expect(metas[1].attributes, <String, String>{'scheme': 'NGE-SEED'});
      expect(metas[2].content, 'NGE-SEED-prefixed');
    });

    // TC-PKG-20 [Boundary value]: an EPUB3 meta with no text and no
    // attributes reads content '' and every optional field null.
    test('TC-PKG-20 [Boundary]: an empty EPUB3 meta reads empty', () {
      final EpubMetadataMeta meta =
          const PackageReader().readMetadataMetaVersion3(_element('<meta/>'));

      expect(meta.content, '');
      expect(meta.id, isNull);
      expect(meta.refines, isNull);
      expect(meta.property, isNull);
      expect(meta.scheme, isNull);
      expect(meta.attributes, isEmpty);
    });

    // TC-PKG-21 [Boundary value]: `dc:description` may repeat, one per
    // language or length, so every one is kept in document order. Every
    // list is empty rather than null when its element is absent.
    test(
        'TC-PKG-21 [Boundary]: every description is kept in order, and an empty '
        'metadata reads empty lists', () {
      final EpubMetadata twoDescriptions = const PackageReader().readMetadata(
        _element('<metadata>'
            '<description>NGE-SEED First</description>'
            '<description>NGE-SEED Last</description>'
            '</metadata>'),
        EpubVersion.epub2,
      );
      final EpubMetadata empty = const PackageReader()
          .readMetadata(_element('<metadata/>'), EpubVersion.epub3);

      expect(twoDescriptions.descriptions,
          <String>['NGE-SEED First', 'NGE-SEED Last']);
      expect(empty.descriptions, isEmpty);
      expect(empty.titles, isEmpty);
      expect(empty.creators, isEmpty);
      expect(empty.identifiers, isEmpty);
      expect(empty.languages, isEmpty);
      expect(empty.metaItems, isEmpty);
    });

    // TC-PKG-22 [Equivalence partitioning]: Dublin Core elements match by
    // lower-cased local name whatever their prefix or case, attributes
    // likewise, and repeated elements keep document order. Real books write
    // `dc:Title` and `opf:role` as often as the canonical spelling.
    test(
        'TC-PKG-22 [Equivalence partitioning]: element and attribute names '
        'match by lower-cased local name, in document order', () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element('<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
            'xmlns:opf="http://www.idpf.org/2007/opf">'
            '<dc:Title>NGE-SEED One</dc:Title>'
            '<dc:TITLE>NGE-SEED Two</dc:TITLE>'
            '<dc:creator opf:role="aut" opf:file-as="Seed, A">'
            'NGE-SEED Creator</dc:creator>'
            '<dc:contributor opf:role="trl" opf:File-As="Seed, B">'
            'NGE-SEED Contributor</dc:contributor>'
            '<dc:identifier opf:scheme="ISBN" ID="isbn">NGE-SEED-ISBN'
            '</dc:identifier>'
            '</metadata>'),
        EpubVersion.epub2,
      );

      expect(metadata.titles, <String>['NGE-SEED One', 'NGE-SEED Two']);
      expect(metadata.creators.single.role, 'aut');
      expect(metadata.creators.single.fileAs, 'Seed, A');
      expect(metadata.contributors.single.role, 'trl');
      expect(metadata.contributors.single.fileAs, 'Seed, B');
      expect(metadata.identifiers.single.scheme, 'ISBN');
      expect(metadata.identifiers.single.id, 'isbn');
    });

    // TC-PKG-23 [Boundary value]: the optional attributes of the structured
    // elements read null when absent, not ''.
    test(
        'TC-PKG-23 [Boundary]: absent creator, contributor, date and '
        'identifier attributes read null', () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element('<metadata>'
            '<creator>NGE-SEED Creator</creator>'
            '<contributor>NGE-SEED Contributor</contributor>'
            '<date>2026</date>'
            '<identifier>NGE-SEED-ID</identifier>'
            '</metadata>'),
        EpubVersion.epub2,
      );

      expect(metadata.creators.single.role, isNull);
      expect(metadata.creators.single.fileAs, isNull);
      expect(metadata.contributors.single.role, isNull);
      expect(metadata.contributors.single.fileAs, isNull);
      expect(metadata.dates.single.event, isNull);
      expect(metadata.dates.single.date, '2026');
      expect(metadata.identifiers.single.id, isNull);
      expect(metadata.identifiers.single.scheme, isNull);
      expect(metadata.identifiers.single.identifier, 'NGE-SEED-ID');
    });
  });

  group('PackageReader.readSpine', () {
    // TC-PKG-11 [Scenario/use-case]: toc, itemrefs and the linear flag are
    // read; foreign children are skipped.
    test(
        'TC-PKG-11 [Scenario]: reads toc and itemrefs and skips foreign '
        'children', () {
      final EpubSpine spine = const PackageReader().readSpine(
        _element('<spine toc="ncx">'
            '<notAnItemRef idref="ignored"/>'
            '<itemref idref="ch1"/>'
            '<itemref idref="ch2" linear="no"/>'
            '</spine>'),
      );

      expect(spine.tableOfContents, 'ncx');
      expect(spine.items, hasLength(2));
      expect(spine.items[0].idRef, 'ch1');
      expect(spine.items[1].idRef, 'ch2');
      // Pinned, not endorsed: `isLinear` is `linear == null || linear == 'no'`,
      // so BOTH an absent attribute and an explicit `linear="no"` report true.
      // Reported to the caller as a suspected inversion; lib/ is not this
      // suite's to change.
      expect(spine.items[0].isLinear, isTrue);
      expect(spine.items[1].isLinear, isTrue);
    });

    // TC-PKG-27 [Equivalence partitioning]: the other side of the same
    // pinned rule — `linear="yes"` reports false — and the `no` comparison
    // ignores case. A spine with no `toc` reads null, which EPUB3 allows.
    test(
        'TC-PKG-27 [Equivalence partitioning]: linear="yes" reports false, '
        '"NO" matches "no", and an absent toc reads null', () {
      final EpubSpine spine = const PackageReader().readSpine(
        _element('<spine>'
            '<itemref idref="ch1" linear="yes"/>'
            '<itemref idref="ch2" linear="NO"/>'
            '</spine>'),
      );

      expect(spine.tableOfContents, isNull);
      expect(spine.items[0].isLinear, isFalse);
      expect(spine.items[1].isLinear, isTrue);
    });

    // TC-PKG-12 [Boundary value]: an itemref must carry a non-empty idref.
    for (final String node in <String>['<itemref/>', '<itemref idref=""/>']) {
      test('TC-PKG-12 [Boundary]: spine $node is rejected', () {
        expect(
          () =>
              const PackageReader().readSpine(_element('<spine>$node</spine>')),
          _throwsMessageContaining('item ID ref is missing'),
        );
      });
    }
  });

  group('PackageReader.readPackage', () {
    String opf({
      String version = '2.0',
      String guide = '',
      String meta = '',
    }) =>
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="$version" '
        'unique-identifier="uid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="uid">urn:uuid:NGE-SEED-PKG</dc:identifier>'
        '<dc:title>NGE-SEED Package</dc:title>'
        '$meta'
        '</metadata>'
        '<manifest>'
        '<item id="ncx" href="toc.ncx" '
        'media-type="application/x-dtbncx+xml"/>'
        '</manifest>'
        '<spine toc="ncx"><itemref idref="ncx"/></spine>'
        '$guide'
        '</package>';

    Uint8List archiveWith(String opfContent,
            {String opfPath = 'content.opf'}) =>
        buildEpubArchive(
          opfPath: opfPath,
          textEntries: <String, String>{opfPath: opfContent},
        );

    // TC-PKG-13 [Scenario/use-case]: a whole package assembles version,
    // metadata, manifest, spine and the optional guide.
    test(
        'TC-PKG-13 [Scenario]: assembles every package section including the '
        'optional guide', () async {
      final EpubPackage package = await const PackageReader().readPackage(
        ZipDecoder().decodeBytes(
          archiveWith(
            opf(
              guide: '<guide><reference type="cover" title="NGE-SEED Cover" '
                  'href="cover.xhtml"/></guide>',
            ),
          ),
        ),
        'content.opf',
      );

      expect(package.version, EpubVersion.epub2);
      expect(package.metadata.titles, <String>['NGE-SEED Package']);
      expect(package.manifest.items.single.id, 'ncx');
      expect(package.spine.tableOfContents, 'ncx');
      expect(package.guide!.items.single.href, 'cover.xhtml');
    });

    // TC-PKG-14 [Equivalence partitioning]: a package with no guide leaves
    // guide null instead of an empty guide.
    test(
        'TC-PKG-14 [Equivalence partitioning]: a package without a guide '
        'leaves guide null', () async {
      final EpubPackage package = await const PackageReader().readPackage(
        ZipDecoder().decodeBytes(archiveWith(opf())),
        'content.opf',
      );

      expect(package.guide, isNull);
    });

    // TC-PKG-15 [Equivalence partitioning]: only 2.0 and 3.0 are accepted;
    // anything else — including an absent version — is refused by name.
    test('TC-PKG-15 [Equivalence partitioning]: version 3.0 maps to epub3',
        () async {
      final EpubPackage package = await const PackageReader().readPackage(
        ZipDecoder().decodeBytes(archiveWith(opf(version: '3.0'))),
        'content.opf',
      );

      expect(package.version, EpubVersion.epub3);
    });

    test(
        'TC-PKG-16 [Error guessing]: an unsupported version is rejected by '
        'value', () {
      expect(
        () => const PackageReader().readPackage(
          ZipDecoder().decodeBytes(archiveWith(opf(version: '1.0'))),
          'content.opf',
        ),
        _throwsMessageContaining('Unsupported EPUB version: 1.0'),
      );
    });

    // TC-PKG-28 [Equivalence partitioning]: an absent version attribute is
    // refused like any other unsupported value, naming it as null.
    test(
        'TC-PKG-28 [Equivalence partitioning]: a package with no version is '
        'rejected', () {
      expect(
        () => const PackageReader().readPackage(
          ZipDecoder().decodeBytes(
              archiveWith(opf().replaceFirst(' version="2.0"', ''))),
          'content.opf',
        ),
        throwsA(isA<EpubUnsupportedVersionException>().having(
          (EpubUnsupportedVersionException e) => e.message,
          'message',
          'Unsupported EPUB version: null.',
        )),
      );
    });

    // TC-PKG-29 [Equivalence partitioning]: the package's own version picks
    // the `<meta>` dialect, so the same element reads differently in an EPUB2
    // and an EPUB3 package.
    for (final List<String> row in <List<String>>[
      <String>['2.0', 'NGE-SEED-attribute'],
      <String>['3.0', 'NGE-SEED-text'],
    ]) {
      test(
          'TC-PKG-29 [Equivalence partitioning]: a version ${row[0]} package '
          'reads its meta in that version\'s dialect', () async {
        final EpubPackage package = await const PackageReader().readPackage(
          ZipDecoder().decodeBytes(archiveWith(opf(
            version: row[0],
            meta: '<meta name="cover" property="dcterms:modified" '
                'content="NGE-SEED-attribute">NGE-SEED-text</meta>',
          ))),
          'content.opf',
        );

        expect(package.metadata.metaItems.single.content, row[1]);
      });
    }

    // TC-PKG-18 [Error guessing]: an OPF missing a required section is
    // refused with the typed `EpubMissingElementException` naming the
    // section, so a caller can tell a malformed book from a defect in this
    // package.
    for (final String section in <String>['metadata', 'manifest', 'spine']) {
      test(
        'TC-PKG-18 [Error guessing]: an OPF without a $section section throws '
        'EpubMissingElementException naming it',
        () {
          final String stripped = opf().replaceFirst(
            RegExp('<$section[^>]*(/>|>.*?</$section>)'),
            '',
          );

          expect(
            () => const PackageReader().readPackage(
              ZipDecoder().decodeBytes(archiveWith(stripped)),
              'content.opf',
            ),
            throwsA(isA<EpubMissingElementException>().having(
              (EpubMissingElementException e) => e.message,
              'message',
              'EPUB parsing error: $section not found in the package.',
            )),
          );
        },
      );
    }

    // TC-PKG-17 [Error guessing]: the container names a root file the archive
    // does not contain.
    test(
        'TC-PKG-17 [Error guessing]: a root file missing from the archive is '
        'rejected', () {
      expect(
        () => const PackageReader().readPackage(
          ZipDecoder().decodeBytes(archiveWith(opf())),
          'nge-seed-absent.opf',
        ),
        _throwsMessageContaining('root file not found in archive'),
      );
    });
  });
}
