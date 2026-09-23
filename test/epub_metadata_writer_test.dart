// `EpubMetadataWriter` — the `<metadata>` half of the OPF — branch by branch.
//
// The round trip in `epub_writer_test.dart` walks this file once, with every
// list populated and every optional attribute present. That single path leaves
// the other side of each optional attribute unexecuted, so the branches get
// direct tests here: an all-empty metadata, each optional attribute absent,
// and each of the two `<meta>` dialects.
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_contributor.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_date.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_meta.dart';
import 'package:novel_glide_epub/src/writers/epub_metadata_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// Serialises [meta] on its own, as the root element of a throwaway document.
String _write(EpubMetadata meta, EpubVersion version) {
  final XmlBuilder builder = XmlBuilder();
  const EpubMetadataWriter().writeMetadata(builder, meta, version);
  return builder.buildDocument().toXmlString();
}

/// Metadata holding only what a test names, every other list empty — the
/// state `PackageReader.readMetadata` produces for an empty `<metadata>`
/// element when nothing is named.
EpubMetadata _metadata({
  List<String> titles = const <String>[],
  List<EpubMetadataCreator> creators = const <EpubMetadataCreator>[],
  List<EpubMetadataContributor> contributors =
      const <EpubMetadataContributor>[],
  List<EpubMetadataDate> dates = const <EpubMetadataDate>[],
  List<EpubMetadataIdentifier> identifiers = const <EpubMetadataIdentifier>[],
  List<EpubMetadataMeta> metaItems = const <EpubMetadataMeta>[],
  List<String> descriptions = const <String>[],
}) =>
    EpubMetadata(
      titles: titles,
      identifiers: identifiers,
      languages: const <String>[],
      creators: creators,
      contributors: contributors,
      dates: dates,
      metaItems: metaItems,
      descriptions: descriptions,
    );

/// A single `<meta>` item written in [version]'s dialect.
String _writeMeta(EpubMetadataMeta item, EpubVersion version) =>
    _write(_metadata(metaItems: <EpubMetadataMeta>[item]), version);

void main() {
  group('const EpubMetadataWriter().writeMetadata structure', () {
    // TC-MDW-2 [Boundary value]: every list empty is the zero case — each
    // loop runs and contributes nothing, so the element comes out bare. It
    // still carries the two namespace declarations the rest of the OPF needs.
    test('TC-MDW-2 [Boundary]: empty lists write a bare element', () {
      final String xml = _write(_metadata(), EpubVersion.epub2);

      expect(xml, contains('xmlns:dc="http://purl.org/dc/elements/1.1/"'));
      expect(xml, contains('xmlns:opf="http://www.idpf.org/2007/opf"'));
      expect(XmlDocument.parse(xml).rootElement.childElements, isEmpty);
    });
  });

  group('const EpubMetadataWriter().writeMetadata plain text elements', () {
    // TC-MDW-4 [Equivalence partitioning]: the ten Dublin Core elements whose
    // whole value is their text, each written into the `dc` namespace.
    test('TC-MDW-4 [Equivalence]: every text-only element lands in dc', () {
      final String xml = _write(
        const EpubMetadata(
          titles: <String>['NGE-SEED Title'],
          identifiers: <EpubMetadataIdentifier>[],
          subjects: <String>['NGE-SEED Subject'],
          publishers: <String>['NGE-SEED Publisher'],
          types: <String>['NGE-SEED Type'],
          formats: <String>['NGE-SEED Format'],
          sources: <String>['NGE-SEED Source'],
          languages: <String>['NGE-SEED Language'],
          relations: <String>['NGE-SEED Relation'],
          coverages: <String>['NGE-SEED Coverage'],
          rights: <String>['NGE-SEED Rights'],
        ),
        EpubVersion.epub2,
      );

      <String, String>{
        'title': 'Title',
        'subject': 'Subject',
        'publisher': 'Publisher',
        'type': 'Type',
        'format': 'Format',
        'source': 'Source',
        'language': 'Language',
        'relation': 'Relation',
        'coverage': 'Coverage',
        'rights': 'Rights',
      }.forEach((String element, String text) {
        expect(xml, contains('<dc:$element>NGE-SEED $text</dc:$element>'));
      });
    });

    // TC-MDW-5 [Scenario/use-case]: repeated elements are all written, in
    // order — an EPUB with two titles keeps both.
    test('TC-MDW-5 [Scenario]: a repeated element writes once per entry', () {
      final String xml = _write(
        _metadata(titles: <String>['NGE-SEED First', 'NGE-SEED Second']),
        EpubVersion.epub2,
      );

      expect(
          XmlDocument.parse(xml)
              .rootElement
              .childElements
              .map((XmlElement e) => e.innerText),
          <String>['NGE-SEED First', 'NGE-SEED Second']);
    });

    // TC-MDW-6 [Equivalence partitioning]: every description is written as
    // its own element, in order; with none, no element is written.
    test('TC-MDW-6 [Equivalence]: descriptions are written one each, in order',
        () {
      final String two = _write(
          _metadata(descriptions: <String>['NGE-SEED One', 'NGE-SEED Two']),
          EpubVersion.epub2);
      final String none = _write(_metadata(), EpubVersion.epub2);

      expect(
          two,
          contains('<dc:description>NGE-SEED One</dc:description>'
              '<dc:description>NGE-SEED Two</dc:description>'));
      expect(none, isNot(contains('<dc:description>')));
    });
  });

  group('const EpubMetadataWriter().writeMetadata attributed elements', () {
    // TC-MDW-7 [Scenario/use-case]: a creator carries its role and file-as in
    // the `opf` namespace, with the name as text.
    test('TC-MDW-7 [Scenario]: a creator writes role, file-as and text', () {
      final String xml = _write(
        _metadata(creators: <EpubMetadataCreator>[
          const EpubMetadataCreator(
              creator: 'NGE-SEED Author', role: 'aut', fileAs: 'SEED, NGE'),
        ]),
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
        _metadata(creators: <EpubMetadataCreator>[
          const EpubMetadataCreator(creator: 'NGE-SEED Author'),
        ]),
        EpubVersion.epub2,
      );

      expect(xml, contains('<dc:creator>NGE-SEED Author</dc:creator>'));
    });

    // TC-MDW-9 [Scenario/use-case]: a contributor takes the same two
    // attributes as a creator, on its own element.
    test('TC-MDW-9 [Scenario]: a contributor writes role, file-as and text',
        () {
      final String xml = _write(
        _metadata(contributors: <EpubMetadataContributor>[
          const EpubMetadataContributor(
              contributor: 'NGE-SEED Editor',
              role: 'edt',
              fileAs: 'SEED, Editor'),
        ]),
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
        _metadata(contributors: <EpubMetadataContributor>[
          const EpubMetadataContributor(contributor: 'NGE-SEED Editor'),
        ]),
        EpubVersion.epub2,
      );

      expect(xml, contains('<dc:contributor>NGE-SEED Editor</dc:contributor>'));
    });

    // TC-MDW-11 [Equivalence partitioning]: `event` is the date's only
    // attribute, written into `opf` when present and skipped when not.
    void dateCase(String? event, String opening) {
      test('TC-MDW-11 [Equivalence]: a date with event=$event', () {
        final String xml = _write(
          _metadata(dates: <EpubMetadataDate>[
            EpubMetadataDate(date: '2026-09-21', event: event),
          ]),
          EpubVersion.epub2,
        );

        expect(xml, contains('${opening}2026-09-21</dc:date>'));
      });
    }

    dateCase('publication', '<dc:date opf:event="publication">');
    dateCase(null, '<dc:date>');

    // TC-MDW-12 [Scenario/use-case]: an identifier's `id` is a plain
    // attribute while `scheme` is namespaced — the one element that mixes the
    // two.
    test(
        'TC-MDW-12 [Scenario]: an identifier writes a bare id and an opf '
        'scheme', () {
      final String xml = _write(
        _metadata(identifiers: <EpubMetadataIdentifier>[
          const EpubMetadataIdentifier(
              identifier: 'NGE-SEED-ID', id: 'etextno', scheme: 'URI'),
        ]),
        EpubVersion.epub2,
      );

      expect(
          xml,
          contains('<dc:identifier id="etextno" opf:scheme="URI">'
              'NGE-SEED-ID</dc:identifier>'));
    });

    // TC-MDW-13 [Boundary value]: both identifier attributes are independently
    // optional.
    void identifierCase(String? id, String? scheme, String opening) {
      test('TC-MDW-13 [Boundary]: identifier id=$id scheme=$scheme', () {
        final String xml = _write(
          _metadata(identifiers: <EpubMetadataIdentifier>[
            EpubMetadataIdentifier(
                identifier: 'NGE-SEED-ID', id: id, scheme: scheme),
          ]),
          EpubVersion.epub2,
        );

        expect(xml, contains('${opening}NGE-SEED-ID</dc:identifier>'));
      });
    }

    identifierCase('etextno', null, '<dc:identifier id="etextno">');
    identifierCase(null, 'URI', '<dc:identifier opf:scheme="URI">');
    identifierCase(null, null, '<dc:identifier>');
  });

  group('const EpubMetadataWriter().writeMetadata meta items', () {
    // TC-MDW-14 [Scenario/use-case]: EPUB2 `<meta>` is name/content — the pair
    // that carries the cover convention.
    test('TC-MDW-14 [Scenario]: an EPUB2 meta writes name and content', () {
      final String xml = _writeMeta(
          const EpubMetadataMeta(name: 'cover', content: 'cover-image'),
          EpubVersion.epub2);

      expect(xml, contains('<meta name="cover" content="cover-image"/>'));
    });

    // TC-MDW-15 [Boundary value]: `name` is optional and left off when
    // unset, but `content` is required by EPUB2 and always written — even
    // empty, which is how the reader records a `<meta>` that had none.
    void epub2MetaCase(String? name, String content, String element) {
      test('TC-MDW-15 [Boundary]: EPUB2 meta name=$name content="$content"',
          () {
        final String xml = _writeMeta(
            EpubMetadataMeta(name: name, content: content), EpubVersion.epub2);

        expect(xml, contains(element));
      });
    }

    epub2MetaCase(null, 'cover-image', '<meta content="cover-image"/>');
    epub2MetaCase('cover', '', '<meta name="cover" content=""/>');
    epub2MetaCase(null, '', '<meta content=""/>');

    // TC-MDW-16 [Scenario/use-case]: EPUB3 `<meta>` is a different element
    // entirely — id/refines/property/scheme, none of them namespaced.
    test('TC-MDW-16 [Scenario]: an EPUB3 meta writes its four attributes', () {
      final String xml = _writeMeta(
          const EpubMetadataMeta(
              content: '',
              id: 'meta-1',
              refines: '#etextno',
              property: 'identifier-type',
              scheme: 'onix:codelist5'),
          EpubVersion.epub3);

      expect(
          xml,
          contains('<meta id="meta-1" refines="#etextno" '
              'property="identifier-type" scheme="onix:codelist5"/>'));
    });

    // TC-MDW-17 [Boundary value]: all four EPUB3 attributes are optional, and
    // the EPUB3 dialect has no `content` attribute to fall back on, so a meta
    // with none of them set writes a bare element.
    test('TC-MDW-17 [Boundary]: an empty EPUB3 meta writes a bare element', () {
      final String xml =
          _writeMeta(const EpubMetadataMeta(content: ''), EpubVersion.epub3);

      expect(xml, contains('<meta/>'));
    });

    // TC-MDW-19 [Error guessing]: the EPUB3 writer has no slot for the meta's
    // text, which is where EPUB3 puts the VALUE. Round-tripping an EPUB3 book
    // therefore keeps the refinement and loses what it refines to.
    test('TC-MDW-19 [Error guessing]: an EPUB3 meta drops its text content',
        () {
      final String xml = _writeMeta(
          const EpubMetadataMeta(
              property: 'dcterms:modified',
              content: 'NGE-SEED-2026-09-21T00:00:00Z'),
          EpubVersion.epub3);

      expect(xml, contains('<meta property="dcterms:modified"/>'));
      expect(xml, isNot(contains('NGE-SEED-2026')));
    });

    // TC-MDW-20 [Boundary value]: each EPUB3 attribute is independently
    // optional — set alone, it is the only one written.
    <String, EpubMetadataMeta>{
      '<meta id="meta-1"/>': const EpubMetadataMeta(content: '', id: 'meta-1'),
      '<meta refines="#etextno"/>':
          const EpubMetadataMeta(content: '', refines: '#etextno'),
      '<meta property="identifier-type"/>':
          const EpubMetadataMeta(content: '', property: 'identifier-type'),
      '<meta scheme="onix:codelist5"/>':
          const EpubMetadataMeta(content: '', scheme: 'onix:codelist5'),
    }.forEach((String element, EpubMetadataMeta item) {
      test('TC-MDW-20 [Boundary]: an EPUB3 meta writes only $element', () {
        final String xml = _writeMeta(item, EpubVersion.epub3);

        expect(xml, contains(element));
      });
    });

    // TC-MDW-21 [Equivalence partitioning]: the version picks ONE dialect,
    // not the union of both. The same fully-populated item writes only
    // name/content under EPUB2 and only the four refinement attributes under
    // EPUB3.
    <EpubVersion, String>{
      EpubVersion.epub2: '<meta name="cover" content="cover-image"/>',
      EpubVersion.epub3: '<meta id="meta-1" refines="#etextno" '
          'property="identifier-type" scheme="onix:codelist5"/>',
    }.forEach((EpubVersion version, String element) {
      test('TC-MDW-21 [Equivalence]: $version writes only its own dialect', () {
        final String xml = _writeMeta(
            const EpubMetadataMeta(
                name: 'cover',
                content: 'cover-image',
                id: 'meta-1',
                refines: '#etextno',
                property: 'identifier-type',
                scheme: 'onix:codelist5'),
            version);

        expect(xml, contains(element));
      });
    });
  });
}
