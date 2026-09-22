// `EpubMetadataWriter` — the `<metadata>` half of the OPF — branch by branch.
//
// The round trip in `epub_writer_test.dart` walks this file once, with every
// list populated and every optional attribute present. That single path leaves
// the other side of each `if` and each `?.` unexecuted, so the branches get
// direct tests here: an all-null metadata, an all-empty one, each optional
// attribute absent, and each of the three `<meta>` dialects.
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_contributor.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_date.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_meta.dart';
import 'package:novel_glide_epub/src/writers/epub_metadata_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// Serialises [meta] on its own, as the root element of a throwaway document.
String _write(EpubMetadata? meta, EpubVersion? version) {
  final XmlBuilder builder = XmlBuilder();
  const EpubMetadataWriter().writeMetadata(builder, meta, version);
  return builder.buildDocument().toXmlString();
}

/// metadata with every list allocated but empty — the state
/// `PackageReader.readMetadata` produces for an empty `<metadata>` element.
EpubMetadata _emptyMetadata() => EpubMetadata()
  ..titles = <String>[]
  ..creators = <EpubMetadataCreator>[]
  ..subjects = <String>[]
  ..publishers = <String>[]
  ..contributors = <EpubMetadataContributor>[]
  ..dates = <EpubMetadataDate>[]
  ..types = <String>[]
  ..formats = <String>[]
  ..identifiers = <EpubMetadataIdentifier>[]
  ..sources = <String>[]
  ..languages = <String>[]
  ..relations = <String>[]
  ..coverages = <String>[]
  ..rights = <String>[]
  ..metaItems = <EpubMetadataMeta>[];

void main() {
  group('const EpubMetadataWriter().writeMetadata structure', () {
    // TC-MDW-1 [Boundary value]: nothing set at all. Every list is null, so
    // every `?.forEach` short-circuits and the element comes out bare — but it
    // still carries the two namespace declarations the rest of the OPF needs.
    test('TC-MDW-1 [Boundary]: an all-null metadata writes a bare element', () {
      final String xml = _write(EpubMetadata(), EpubVersion.epub2);

      expect(xml, contains('xmlns:dc="http://purl.org/dc/elements/1.1/"'));
      expect(xml, contains('xmlns:opf="http://www.idpf.org/2007/opf"'));
      expect(XmlDocument.parse(xml).rootElement.childElements, isEmpty);
    });

    // TC-MDW-2 [Boundary value]: allocated-but-empty is the other zero case —
    // each `forEach` runs and contributes nothing.
    test('TC-MDW-2 [Boundary]: empty lists write no children', () {
      final String xml = _write(_emptyMetadata(), EpubVersion.epub2);

      expect(XmlDocument.parse(xml).rootElement.childElements, isEmpty);
    });

    // TC-MDW-3 [Error guessing]: the parameter is nullable but dereferenced
    // with `!`. A caller with no metadata gets a TypeError, not an empty
    // element.
    test('TC-MDW-3 [Error guessing]: a null metadata is not tolerated', () {
      expect(() => _write(null, EpubVersion.epub2), throwsA(isA<TypeError>()));
    });
  });

  group('const EpubMetadataWriter().writeMetadata plain text elements', () {
    // TC-MDW-4 [Equivalence partitioning]: the ten Dublin Core elements whose
    // whole value is their text, each written into the `dc` namespace.
    test('TC-MDW-4 [Equivalence]: every text-only element lands in dc', () {
      final String xml = _write(
        _emptyMetadata()
          ..titles = <String>['NGE-SEED Title']
          ..subjects = <String>['NGE-SEED Subject']
          ..publishers = <String>['NGE-SEED Publisher']
          ..types = <String>['NGE-SEED Type']
          ..formats = <String>['NGE-SEED Format']
          ..sources = <String>['NGE-SEED Source']
          ..languages = <String>['NGE-SEED Language']
          ..relations = <String>['NGE-SEED Relation']
          ..coverages = <String>['NGE-SEED Coverage']
          ..rights = <String>['NGE-SEED Rights'],
        EpubVersion.epub2,
      );

      for (final List<String> pair in <List<String>>[
        <String>['title', 'Title'],
        <String>['subject', 'Subject'],
        <String>['publisher', 'Publisher'],
        <String>['type', 'Type'],
        <String>['format', 'Format'],
        <String>['source', 'Source'],
        <String>['language', 'Language'],
        <String>['relation', 'Relation'],
        <String>['coverage', 'Coverage'],
        <String>['rights', 'Rights'],
      ]) {
        expect(xml,
            contains('<dc:${pair[0]}>NGE-SEED ${pair[1]}</dc:${pair[0]}>'));
      }
    });

    // TC-MDW-5 [Scenario/use-case]: repeated elements are all written, in
    // order — an EPUB with two titles keeps both.
    test('TC-MDW-5 [Scenario]: a repeated element writes once per entry', () {
      final String xml = _write(
        _emptyMetadata()
          ..titles = <String>['NGE-SEED First', 'NGE-SEED Second'],
        EpubVersion.epub2,
      );

      expect(
          XmlDocument.parse(xml)
              .rootElement
              .childElements
              .map((XmlElement e) => e.innerText),
          <String>['NGE-SEED First', 'NGE-SEED Second']);
    });

    // TC-MDW-6 [Equivalence partitioning]: `description` is the one element
    // written outside the cascade, after everything else, and only when set.
    for (final List<Object?> row in <List<Object?>>[
      <Object?>['NGE-SEED Description', true],
      <Object?>[null, false],
    ]) {
      test('TC-MDW-6 [Equivalence]: description=${row[0]} is written=${row[1]}',
          () {
        final String xml = _write(
          _emptyMetadata()..description = row[0] as String?,
          EpubVersion.epub2,
        );

        expect(xml.contains('<dc:description>'), row[1]);
      });
    }
  });

  group('const EpubMetadataWriter().writeMetadata attributed elements', () {
    // TC-MDW-7 [Scenario/use-case]: a creator carries its role and file-as in
    // the `opf` namespace, with the name as text.
    test('TC-MDW-7 [Scenario]: a creator writes role, file-as and text', () {
      final String xml = _write(
        _emptyMetadata()
          ..creators = <EpubMetadataCreator>[
            EpubMetadataCreator()
              ..creator = 'NGE-SEED Author'
              ..role = 'aut'
              ..fileAs = 'SEED, NGE',
          ],
        EpubVersion.epub2,
      );

      expect(
          xml,
          contains('<dc:creator opf:role="aut" opf:file-as="SEED, NGE">'
              'NGE-SEED Author</dc:creator>'));
    });

    // TC-MDW-8 [Boundary value]: both creator attributes are optional and are
    // omitted rather than written empty.
    test(
        'TC-MDW-8 [Boundary]: a creator with no role or file-as writes only '
        'its text', () {
      final String xml = _write(
        _emptyMetadata()
          ..creators = <EpubMetadataCreator>[
            EpubMetadataCreator()..creator = 'NGE-SEED Author',
          ],
        EpubVersion.epub2,
      );

      expect(xml, contains('<dc:creator>NGE-SEED Author</dc:creator>'));
    });

    // TC-MDW-9 [Scenario/use-case]: a contributor takes the same two
    // attributes as a creator, on its own element.
    test('TC-MDW-9 [Scenario]: a contributor writes role, file-as and text',
        () {
      final String xml = _write(
        _emptyMetadata()
          ..contributors = <EpubMetadataContributor>[
            EpubMetadataContributor()
              ..contributor = 'NGE-SEED Editor'
              ..role = 'edt'
              ..fileAs = 'SEED, Editor',
          ],
        EpubVersion.epub2,
      );

      expect(
          xml,
          contains('<dc:contributor opf:role="edt" opf:file-as="SEED, Editor">'
              'NGE-SEED Editor</dc:contributor>'));
    });

    // TC-MDW-10 [Boundary value]: and omits both when unset.
    test(
        'TC-MDW-10 [Boundary]: a contributor with no role or file-as writes '
        'only its text', () {
      final String xml = _write(
        _emptyMetadata()
          ..contributors = <EpubMetadataContributor>[
            EpubMetadataContributor()..contributor = 'NGE-SEED Editor',
          ],
        EpubVersion.epub2,
      );

      expect(xml, contains('<dc:contributor>NGE-SEED Editor</dc:contributor>'));
    });

    // TC-MDW-11 [Equivalence partitioning]: `event` is the date's only
    // attribute, written into `opf` when present and skipped when not.
    for (final List<Object?> row in <List<Object?>>[
      <Object?>['publication', '<dc:date opf:event="publication">'],
      <Object?>[null, '<dc:date>'],
    ]) {
      test('TC-MDW-11 [Equivalence]: a date with event=${row[0]}', () {
        final String xml = _write(
          _emptyMetadata()
            ..dates = <EpubMetadataDate>[
              EpubMetadataDate()
                ..date = '2026-09-21'
                ..event = row[0] as String?,
            ],
          EpubVersion.epub2,
        );

        expect(xml, contains('${row[1]}2026-09-21</dc:date>'));
      });
    }

    // TC-MDW-12 [Scenario/use-case]: an identifier's `id` is a plain
    // attribute while `scheme` is namespaced — the one element that mixes the
    // two.
    test(
        'TC-MDW-12 [Scenario]: an identifier writes a bare id and an opf '
        'scheme', () {
      final String xml = _write(
        _emptyMetadata()
          ..identifiers = <EpubMetadataIdentifier>[
            EpubMetadataIdentifier()
              ..identifier = 'NGE-SEED-ID'
              ..id = 'etextno'
              ..scheme = 'URI',
          ],
        EpubVersion.epub2,
      );

      expect(
          xml,
          contains('<dc:identifier id="etextno" opf:scheme="URI">'
              'NGE-SEED-ID</dc:identifier>'));
    });

    // TC-MDW-13 [Boundary value]: both identifier attributes are independently
    // optional.
    for (final List<Object?> row in <List<Object?>>[
      <Object?>['etextno', null, '<dc:identifier id="etextno">'],
      <Object?>[null, 'URI', '<dc:identifier opf:scheme="URI">'],
      <Object?>[null, null, '<dc:identifier>'],
    ]) {
      test('TC-MDW-13 [Boundary]: identifier id=${row[0]} scheme=${row[1]}',
          () {
        final String xml = _write(
          _emptyMetadata()
            ..identifiers = <EpubMetadataIdentifier>[
              EpubMetadataIdentifier()
                ..identifier = 'NGE-SEED-ID'
                ..id = row[0] as String?
                ..scheme = row[1] as String?,
            ],
          EpubVersion.epub2,
        );

        expect(xml, contains('${row[2]}NGE-SEED-ID</dc:identifier>'));
      });
    }
  });

  group('const EpubMetadataWriter().writeMetadata meta items', () {
    // TC-MDW-14 [Scenario/use-case]: EPUB2 `<meta>` is name/content — the pair
    // that carries the cover convention.
    test('TC-MDW-14 [Scenario]: an EPUB2 meta writes name and content', () {
      final String xml = _write(
        _emptyMetadata()
          ..metaItems = <EpubMetadataMeta>[
            EpubMetadataMeta()
              ..name = 'cover'
              ..content = 'cover-image',
          ],
        EpubVersion.epub2,
      );

      expect(xml, contains('<meta name="cover" content="cover-image"/>'));
    });

    // TC-MDW-15 [Boundary value]: each EPUB2 attribute is written only when
    // set, so a half-filled meta does not emit an empty one.
    for (final List<Object?> row in <List<Object?>>[
      <Object?>['cover', null, '<meta name="cover"/>'],
      <Object?>[null, 'cover-image', '<meta content="cover-image"/>'],
      <Object?>[null, null, '<meta/>'],
    ]) {
      test('TC-MDW-15 [Boundary]: EPUB2 meta name=${row[0]} content=${row[1]}',
          () {
        final String xml = _write(
          _emptyMetadata()
            ..metaItems = <EpubMetadataMeta>[
              EpubMetadataMeta()
                ..name = row[0] as String?
                ..content = row[1] as String?,
            ],
          EpubVersion.epub2,
        );

        expect(xml, contains(row[2] as String));
      });
    }

    // TC-MDW-16 [Scenario/use-case]: EPUB3 `<meta>` is a different element
    // entirely — id/refines/property/scheme, none of them namespaced.
    test('TC-MDW-16 [Scenario]: an EPUB3 meta writes its four attributes', () {
      final String xml = _write(
        _emptyMetadata()
          ..metaItems = <EpubMetadataMeta>[
            EpubMetadataMeta()
              ..id = 'meta-1'
              ..refines = '#etextno'
              ..property = 'identifier-type'
              ..scheme = 'onix:codelist5',
          ],
        EpubVersion.epub3,
      );

      expect(
          xml,
          contains('<meta id="meta-1" refines="#etextno" '
              'property="identifier-type" scheme="onix:codelist5"/>'));
    });

    // TC-MDW-17 [Boundary value]: all four EPUB3 attributes are optional.
    test('TC-MDW-17 [Boundary]: an empty EPUB3 meta writes a bare element', () {
      final String xml = _write(
        _emptyMetadata()..metaItems = <EpubMetadataMeta>[EpubMetadataMeta()],
        EpubVersion.epub3,
      );

      expect(xml, contains('<meta/>'));
    });

    // TC-MDW-18 [Equivalence partitioning]: the version switch has a third
    // arm — neither EPUB2 nor EPUB3 — under which a meta item writes an empty
    // element rather than guessing a dialect. `PackageReader` cannot produce a
    // null version, so this is reachable only by a hand-built package.
    test(
        'TC-MDW-18 [Equivalence]: an unknown version writes meta with no '
        'attributes', () {
      final String xml = _write(
        _emptyMetadata()
          ..metaItems = <EpubMetadataMeta>[
            EpubMetadataMeta()
              ..name = 'cover'
              ..content = 'cover-image'
              ..id = 'meta-1',
          ],
        null,
      );

      expect(xml, contains('<meta/>'));
    });

    // TC-MDW-19 [Error guessing]: the EPUB3 writer has no slot for the meta's
    // text, which is where EPUB3 puts the VALUE. Round-tripping an EPUB3 book
    // therefore keeps the refinement and loses what it refines to.
    test('TC-MDW-19 [Error guessing]: an EPUB3 meta drops its text content',
        () {
      final String xml = _write(
        _emptyMetadata()
          ..metaItems = <EpubMetadataMeta>[
            EpubMetadataMeta()
              ..property = 'dcterms:modified'
              ..content = 'NGE-SEED-2026-09-21T00:00:00Z',
          ],
        EpubVersion.epub3,
      );

      expect(xml, contains('<meta property="dcterms:modified"/>'));
      expect(xml, isNot(contains('NGE-SEED-2026')));
    });
  });
}
