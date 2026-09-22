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
      expect(guide.items!.single.type, 'cover');
      expect(guide.items!.single.title, 'NGE-SEED Cover');
      expect(guide.items!.single.href, 'cover.xhtml');
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
      final EpubManifestItem item = manifest.items!.single;
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
      expect(metadata.description, 'NGE-SEED Description');
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

      expect(metadata.creators!.single.creator, 'NGE-SEED Creator');
      expect(metadata.creators!.single.role, 'aut');
      expect(metadata.creators!.single.fileAs, 'Seed, A');
      expect(metadata.contributors!.single.contributor, 'NGE-SEED Contributor');
      expect(metadata.contributors!.single.role, 'trl');
      expect(metadata.contributors!.single.fileAs, 'Seed, B');
      expect(metadata.dates!.single.date, '2026-09-21');
      expect(metadata.dates!.single.event, 'publication');
      expect(metadata.identifiers!.single.identifier, 'urn:uuid:NGE-SEED');
      expect(metadata.identifiers!.single.id, 'uid');
      expect(metadata.identifiers!.single.scheme, 'URN');
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
    // plus element text, and an unknown version reads no meta at all.
    test(
        'TC-PKG-8 [Equivalence partitioning]: EPUB2 meta reads name and '
        'content attributes', () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element('<metadata><meta name="cover" content="cover-img"/>'
            '</metadata>'),
        EpubVersion.epub2,
      );

      expect(metadata.metaItems!.single.name, 'cover');
      expect(metadata.metaItems!.single.content, 'cover-img');
    });

    test(
        'TC-PKG-9 [Equivalence partitioning]: EPUB3 meta reads the property '
        'dialect and the element text', () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element('<metadata>'
            '<meta id="m1" refines="#uid" property="identifier-type" '
            'scheme="onix:codelist5">15</meta>'
            '</metadata>'),
        EpubVersion.epub3,
      );

      final EpubMetadataMeta meta = metadata.metaItems!.single;
      expect(meta.id, 'm1');
      expect(meta.refines, '#uid');
      expect(meta.property, 'identifier-type');
      expect(meta.scheme, 'onix:codelist5');
      expect(meta.content, '15');
      expect(meta.attributes, <String, String>{
        'id': 'm1',
        'refines': '#uid',
        'property': 'identifier-type',
        'scheme': 'onix:codelist5',
      });
    });

    test(
        'TC-PKG-10 [Equivalence partitioning]: a null EPUB version collects '
        'no meta items', () {
      final EpubMetadata metadata = const PackageReader().readMetadata(
        _element('<metadata><meta name="cover" content="cover-img"/>'
            '</metadata>'),
        null,
      );

      expect(metadata.metaItems, isEmpty);
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
      expect(spine.items![0].idRef, 'ch1');
      expect(spine.items![1].idRef, 'ch2');
      // Pinned, not endorsed: `isLinear` is `linear == null || linear == 'no'`,
      // so BOTH an absent attribute and an explicit `linear="no"` report true.
      // Reported to the caller as a suspected inversion; lib/ is not this
      // suite's to change.
      expect(spine.items![0].isLinear, isTrue);
      expect(spine.items![1].isLinear, isTrue);
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
    }) =>
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="$version" '
        'unique-identifier="uid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="uid">urn:uuid:NGE-SEED-PKG</dc:identifier>'
        '<dc:title>NGE-SEED Package</dc:title>'
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
      expect(package.metadata!.titles, <String>['NGE-SEED Package']);
      expect(package.manifest!.items!.single.id, 'ncx');
      expect(package.spine!.tableOfContents, 'ncx');
      expect(package.guide!.items!.single.href, 'cover.xhtml');
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

    // TC-PKG-18 [Error guessing]: an OPF missing a required section surfaces
    // as a raw StateError from `firstWhere`, NOT as the parser's own
    // 'metadata/manifest/spine not found in the package' Exception — those
    // three guards test a value that can never be null, so they are dead
    // code. Pinned here because this is a trust boundary: the caller sees a
    // StateError, and any handler written against the Exception text would
    // never fire. Reported to the caller; the fix belongs in lib/.
    for (final String section in <String>['metadata', 'manifest', 'spine']) {
      test(
        'TC-PKG-18 [Error guessing]: an OPF without a $section section throws '
        'StateError, not the parser Exception',
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
            throwsA(isA<StateError>()),
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
