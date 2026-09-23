// The OPF body writers: `EpubPackageWriter` and the three small ones it calls
// for `<manifest>`, `<spine>` and `<guide>`.
//
// `EpubMetadataWriter` is the fourth and has its own file; this one asserts
// only that the package writer wires it in.
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_metadata_meta.dart';
import 'package:novel_glide_epub/src/writers/epub_guide_writer.dart';
import 'package:novel_glide_epub/src/writers/epub_manifest_writer.dart';
import 'package:novel_glide_epub/src/writers/epub_package_writer.dart';
import 'package:novel_glide_epub/src/writers/epub_spine_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// Runs [write] against a fresh builder and returns the document it produced.
String _build(void Function(XmlBuilder builder) write) {
  final XmlBuilder builder = XmlBuilder();
  write(builder);
  return builder.buildDocument().toXmlString();
}

const EpubMetadata _minimalMetadata = EpubMetadata(
  titles: <String>['NGE-SEED Title'],
  identifiers: <EpubMetadataIdentifier>[],
  languages: <String>[],
);

/// The smallest package `const EpubPackageWriter().writeContent` accepts,
/// with an empty guide unless [guide] is given; [metadata] replaces the
/// one-title default.
EpubPackage _minimalPackage(
  EpubVersion version, {
  EpubMetadata metadata = _minimalMetadata,
  EpubGuide? guide = const EpubGuide(items: <EpubGuideReference>[]),
}) =>
    EpubPackage(
      version: version,
      metadata: metadata,
      manifest: const EpubManifest(items: <EpubManifestItem>[
        EpubManifestItem(
            id: 'ncx', href: 'toc.ncx', mediaType: 'application/x-dtbncx+xml'),
      ]),
      spine: const EpubSpine(
          tableOfContents: 'ncx', ltr: true, items: <EpubSpineItemRef>[]),
      guide: guide,
    );

void main() {
  group('const EpubManifestWriter().writeManifest', () {
    // TC-PKW-1 [Scenario/use-case]: an item is written as its three required
    // attributes.
    test('TC-PKW-1 [Scenario]: each item writes id, href and media-type', () {
      final String xml =
          _build((XmlBuilder b) => const EpubManifestWriter().writeManifest(
              b,
              const EpubManifest(items: <EpubManifestItem>[
                EpubManifestItem(
                    id: 'ch1',
                    href: 'chapter1.xhtml',
                    mediaType: 'application/xhtml+xml'),
                EpubManifestItem(
                    id: 'css', href: 'style.css', mediaType: 'text/css'),
              ])));

      expect(
          xml,
          '<manifest>'
          '<item id="ch1" href="chapter1.xhtml" '
          'media-type="application/xhtml+xml"/>'
          '<item id="css" href="style.css" media-type="text/css"/>'
          '</manifest>');
    });

    // TC-PKW-2 [Boundary value]: an empty manifest is an empty element, not an
    // error.
    test('TC-PKW-2 [Boundary]: an empty manifest writes a bare element', () {
      final String xml = _build((XmlBuilder b) => const EpubManifestWriter()
          .writeManifest(b, const EpubManifest(items: <EpubManifestItem>[])));

      expect(xml, '<manifest/>');
    });

    // TC-PKW-3 [Error guessing]: the six other attributes `PackageReader`
    // reads off a manifest item — the fallback chain and `properties`, which
    // is how EPUB3 marks its nav document — have no writer, so they are
    // silently dropped.
    test(
        'TC-PKW-3 [Error guessing]: properties and the fallback chain are '
        'dropped', () {
      final String xml =
          _build((XmlBuilder b) => const EpubManifestWriter().writeManifest(
              b,
              const EpubManifest(items: <EpubManifestItem>[
                EpubManifestItem(
                  id: 'nav',
                  href: 'nav.xhtml',
                  mediaType: 'application/xhtml+xml',
                  properties: 'nav',
                  fallback: 'NGE-SEED-fallback',
                  fallbackStyle: 'NGE-SEED-fallback-style',
                  mediaOverlay: 'NGE-SEED-overlay',
                  requiredNamespace: 'NGE-SEED-ns',
                  requiredModules: 'NGE-SEED-modules',
                ),
              ])));

      expect(xml, isNot(contains('NGE-SEED')));
      expect(xml, isNot(contains('properties')));
    });
  });

  group('const EpubSpineWriter().writeSpine', () {
    // TC-PKW-6 [Equivalence partitioning]: `isLinear` is the only spine item
    // state, and it maps to the two spellings of the attribute.
    test('TC-PKW-6 [Equivalence]: linearity maps to yes and no', () {
      final String xml = _build((XmlBuilder b) => const EpubSpineWriter()
          .writeSpine(
              b,
              const EpubSpine(
                  tableOfContents: 'ncx',
                  ltr: true,
                  items: <EpubSpineItemRef>[
                    EpubSpineItemRef(idRef: 'ch1', isLinear: true),
                    EpubSpineItemRef(idRef: 'ch2', isLinear: false),
                  ])));

      expect(
          xml,
          '<spine toc="ncx">'
          '<itemref idref="ch1" linear="yes"/>'
          '<itemref idref="ch2" linear="no"/>'
          '</spine>');
    });

    // TC-PKW-7 [Boundary value]: a spine with no items still writes its `toc`.
    test('TC-PKW-7 [Boundary]: an empty spine keeps its toc attribute', () {
      final String xml = _build((XmlBuilder b) => const EpubSpineWriter()
          .writeSpine(
              b,
              const EpubSpine(
                  tableOfContents: 'ncx',
                  ltr: true,
                  items: <EpubSpineItemRef>[])));

      expect(xml, '<spine toc="ncx"/>');
    });

    // TC-PKW-8 [Equivalence partitioning]: `toc` is optional in EPUB3 and
    // `readSpine` leaves it null there. A null toc is the other side of the
    // partition from TC-PKW-7: the attribute is left off, not written empty,
    // and the items are written as usual.
    test('TC-PKW-8 [Equivalence]: a spine with no toc omits the attribute', () {
      final String xml =
          _build((XmlBuilder b) => const EpubSpineWriter().writeSpine(
              b,
              const EpubSpine(ltr: true, items: <EpubSpineItemRef>[
                EpubSpineItemRef(idRef: 'ch1', isLinear: true),
              ])));

      expect(xml, '<spine><itemref idref="ch1" linear="yes"/></spine>');
    });

    // TC-PKW-9 [Error guessing]: `page-progression-direction` has no writer,
    // so a right-to-left book — the vertical-writing case this parser exists
    // for — loses its direction.
    test('TC-PKW-9 [Error guessing]: the reading direction is dropped', () {
      final String xml = _build((XmlBuilder b) => const EpubSpineWriter()
          .writeSpine(
              b,
              const EpubSpine(
                  tableOfContents: 'ncx',
                  ltr: false,
                  items: <EpubSpineItemRef>[])));

      expect(xml, isNot(contains('page-progression-direction')));
    });
  });

  group('const EpubGuideWriter().writeGuide', () {
    // TC-PKW-10 [Scenario/use-case]: a guide reference writes its three
    // attributes.
    test('TC-PKW-10 [Scenario]: each reference writes type, title and href',
        () {
      final String xml =
          _build((XmlBuilder b) => const EpubGuideWriter().writeGuide(
              b,
              const EpubGuide(items: <EpubGuideReference>[
                EpubGuideReference(
                    type: 'toc',
                    title: 'NGE-SEED Contents',
                    href: 'chapter1.xhtml'),
              ])));

      expect(
          xml,
          '<guide><reference type="toc" title="NGE-SEED Contents" '
          'href="chapter1.xhtml"/></guide>');
    });

    // TC-PKW-11 [Boundary value]: an empty guide is an empty element.
    test('TC-PKW-11 [Boundary]: an empty guide writes a bare element', () {
      final String xml = _build((XmlBuilder b) => const EpubGuideWriter()
          .writeGuide(b, const EpubGuide(items: <EpubGuideReference>[])));

      expect(xml, '<guide/>');
    });

    // TC-PKW-12 [Boundary value]: `title` is optional in the OPF, and
    // `PackageReader` requires only `type` and `href`. A titleless reference
    // writes those two and leaves `title` off rather than writing it empty.
    test('TC-PKW-12 [Boundary]: a reference with no title omits the attribute',
        () {
      final String xml =
          _build((XmlBuilder b) => const EpubGuideWriter().writeGuide(
              b,
              const EpubGuide(items: <EpubGuideReference>[
                EpubGuideReference(type: 'toc', href: 'chapter1.xhtml'),
              ])));

      expect(
          xml, '<guide><reference type="toc" href="chapter1.xhtml"/></guide>');
    });
  });

  group('const EpubPackageWriter().writeContent', () {
    // TC-PKW-14 [Equivalence partitioning]: the version attribute is the one
    // thing the package element decides, one spelling per version.
    <EpubVersion, String>{
      EpubVersion.epub2: '2.0',
      EpubVersion.epub3: '3.0',
    }.forEach((EpubVersion version, String written) {
      test('TC-PKW-14 [Equivalence]: version $version writes $written', () {
        final String xml =
            const EpubPackageWriter().writeContent(_minimalPackage(version));

        expect(xml, contains('version="$written"'));
      });
    });

    // TC-PKW-15 [Scenario/use-case]: the four sections are emitted in OPF
    // order, inside the package namespace, under an XML declaration.
    test(
        'TC-PKW-15 [Scenario]: emits metadata, manifest, spine and guide in '
        'order', () {
      final String xml = const EpubPackageWriter()
          .writeContent(_minimalPackage(EpubVersion.epub2));

      final XmlElement package = XmlDocument.parse(xml).rootElement;
      expect(xml, startsWith('<?xml version="1.0"?>'));
      expect(package.name.local, 'package');
      expect(package.getAttribute('xmlns'), 'http://www.idpf.org/2007/opf');
      expect(package.getAttribute('unique-identifier'), 'etextno');
      expect(package.childElements.map((XmlElement e) => e.name.local),
          <String>['metadata', 'manifest', 'spine', 'guide']);
    });

    // TC-PKW-13 [Equivalence partitioning]: a package with no guide — what
    // the reader produces for an OPF with no `<guide>`, the norm in EPUB 3 —
    // is the other side of TC-PKW-15. The guide is optional in the OPF, so
    // the element is left out entirely rather than written empty.
    test('TC-PKW-13 [Equivalence]: a package with no guide writes no guide',
        () {
      final String xml = const EpubPackageWriter()
          .writeContent(_minimalPackage(EpubVersion.epub3, guide: null));

      expect(
          XmlDocument.parse(xml)
              .rootElement
              .childElements
              .map((XmlElement e) => e.name.local),
          <String>['metadata', 'manifest', 'spine']);
    });

    // TC-PKW-16 [Scenario/use-case]: the metadata writer really is wired in —
    // a title and a meta item set on the package reach the output, in the
    // dialect of the package's own version.
    test('TC-PKW-16 [Scenario]: package metadata reaches the document', () {
      final String xml = const EpubPackageWriter().writeContent(_minimalPackage(
        EpubVersion.epub2,
        metadata: const EpubMetadata(
          titles: <String>['NGE-SEED Title'],
          identifiers: <EpubMetadataIdentifier>[],
          languages: <String>[],
          metaItems: <EpubMetadataMeta>[
            EpubMetadataMeta(name: 'cover', content: 'cover-image'),
          ],
        ),
      ));

      expect(xml, contains('<dc:title>NGE-SEED Title</dc:title>'));
      expect(xml, contains('<meta name="cover" content="cover-image"/>'));
    });

    // TC-PKW-17 [Error guessing]: `unique-identifier` is written as the
    // constant `etextno` regardless of what the metadata's identifiers are
    // actually called, so a package whose identifier carries another id comes
    // back pointing at nothing.
    test(
        'TC-PKW-17 [Error guessing]: unique-identifier is a constant, not the '
        "identifier's id", () {
      final String xml = const EpubPackageWriter().writeContent(_minimalPackage(
        EpubVersion.epub2,
        metadata: const EpubMetadata(
          titles: <String>['NGE-SEED Title'],
          identifiers: <EpubMetadataIdentifier>[
            EpubMetadataIdentifier(
                id: 'NGE-SEED-uuid', identifier: 'NGE-SEED-ID'),
          ],
          languages: <String>[],
        ),
      ));

      expect(xml, contains('unique-identifier="etextno"'));
      expect(xml, contains('<dc:identifier id="NGE-SEED-uuid">'));
    });
  });
}
