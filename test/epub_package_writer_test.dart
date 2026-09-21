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

EpubManifestItem _item(String id, String href, String mediaType) =>
    EpubManifestItem()
      ..Id = id
      ..Href = href
      ..MediaType = mediaType;

/// The smallest package `const EpubPackageWriter().writeContent` accepts: metadata,
/// manifest, spine and guide all non-null.
EpubPackage _minimalPackage(EpubVersion? version) => EpubPackage()
  ..Version = version
  ..Metadata = (EpubMetadata()..Titles = <String>['NGE-SEED Title'])
  ..Manifest = (EpubManifest()
    ..Items = <EpubManifestItem>[
      _item('ncx', 'toc.ncx', 'application/x-dtbncx+xml'),
    ])
  ..Spine = (EpubSpine()
    ..TableOfContents = 'ncx'
    ..Items = <EpubSpineItemRef>[])
  ..Guide = (EpubGuide()..Items = <EpubGuideReference>[]);

void main() {
  group('const EpubManifestWriter().writeManifest', () {
    // TC-PKW-1 [Scenario/use-case]: an item is written as its three required
    // attributes.
    test('TC-PKW-1 [Scenario]: each item writes id, href and media-type', () {
      final String xml =
          _build((XmlBuilder b) => const EpubManifestWriter().writeManifest(
              b,
              EpubManifest()
                ..Items = <EpubManifestItem>[
                  _item('ch1', 'chapter1.xhtml', 'application/xhtml+xml'),
                  _item('css', 'style.css', 'text/css'),
                ]));

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
          .writeManifest(b, EpubManifest()..Items = <EpubManifestItem>[]));

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
              EpubManifest()
                ..Items = <EpubManifestItem>[
                  _item('nav', 'nav.xhtml', 'application/xhtml+xml')
                    ..Properties = 'nav'
                    ..Fallback = 'NGE-SEED-fallback'
                    ..FallbackStyle = 'NGE-SEED-fallback-style'
                    ..MediaOverlay = 'NGE-SEED-overlay'
                    ..RequiredNamespace = 'NGE-SEED-ns'
                    ..RequiredModules = 'NGE-SEED-modules',
                ]));

      expect(xml, isNot(contains('NGE-SEED')));
      expect(xml, isNot(contains('properties')));
    });

    // TC-PKW-4 [Error guessing]: every attribute is dereferenced with `!`, so
    // an item the reader never produced — one with no media type — throws
    // rather than writing a partial element.
    test('TC-PKW-4 [Error guessing]: an item with no media type throws', () {
      expect(
          () =>
              _build((XmlBuilder b) => const EpubManifestWriter().writeManifest(
                  b,
                  EpubManifest()
                    ..Items = <EpubManifestItem>[
                      EpubManifestItem()
                        ..Id = 'ch1'
                        ..Href = 'chapter1.xhtml',
                    ])),
          throwsA(isA<TypeError>()));
    });

    // TC-PKW-5 [Error guessing]: the manifest parameter is nullable and
    // dereferenced with `!`.
    test('TC-PKW-5 [Error guessing]: a null manifest is not tolerated', () {
      expect(
          () => _build((XmlBuilder b) =>
              const EpubManifestWriter().writeManifest(b, null)),
          throwsA(isA<TypeError>()));
    });
  });

  group('const EpubSpineWriter().writeSpine', () {
    // TC-PKW-6 [Equivalence partitioning]: `IsLinear` is the only spine item
    // state, and it maps to the two spellings of the attribute.
    test('TC-PKW-6 [Equivalence]: linearity maps to yes and no', () {
      final String xml =
          _build((XmlBuilder b) => const EpubSpineWriter().writeSpine(
              b,
              EpubSpine()
                ..TableOfContents = 'ncx'
                ..Items = <EpubSpineItemRef>[
                  EpubSpineItemRef()
                    ..IdRef = 'ch1'
                    ..IsLinear = true,
                  EpubSpineItemRef()
                    ..IdRef = 'ch2'
                    ..IsLinear = false,
                ]));

      expect(
          xml,
          '<spine toc="ncx">'
          '<itemref idref="ch1" linear="yes"/>'
          '<itemref idref="ch2" linear="no"/>'
          '</spine>');
    });

    // TC-PKW-7 [Boundary value]: a spine with no items still writes its `toc`.
    test('TC-PKW-7 [Boundary]: an empty spine keeps its toc attribute', () {
      final String xml =
          _build((XmlBuilder b) => const EpubSpineWriter().writeSpine(
              b,
              EpubSpine()
                ..TableOfContents = 'ncx'
                ..Items = <EpubSpineItemRef>[]));

      expect(xml, '<spine toc="ncx"/>');
    });

    // TC-PKW-8 [Error guessing]: `toc` is optional in EPUB3 and `readSpine`
    // leaves it null there, but the writer requires it — so an EPUB3 book
    // cannot be written back out.
    test('TC-PKW-8 [Error guessing]: a spine with no toc throws', () {
      expect(
          () => _build((XmlBuilder b) => const EpubSpineWriter()
              .writeSpine(b, EpubSpine()..Items = <EpubSpineItemRef>[])),
          throwsA(isA<TypeError>()));
    });

    // TC-PKW-9 [Error guessing]: `page-progression-direction` has no writer,
    // so a right-to-left book — the vertical-writing case this parser exists
    // for — loses its direction.
    test('TC-PKW-9 [Error guessing]: the reading direction is dropped', () {
      final String xml =
          _build((XmlBuilder b) => const EpubSpineWriter().writeSpine(
              b,
              EpubSpine()
                ..TableOfContents = 'ncx'
                ..ltr = false
                ..Items = <EpubSpineItemRef>[]));

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
              EpubGuide()
                ..Items = <EpubGuideReference>[
                  EpubGuideReference()
                    ..Type = 'toc'
                    ..Title = 'NGE-SEED Contents'
                    ..Href = 'chapter1.xhtml',
                ]));

      expect(
          xml,
          '<guide><reference type="toc" title="NGE-SEED Contents" '
          'href="chapter1.xhtml"/></guide>');
    });

    // TC-PKW-11 [Boundary value]: an empty guide is an empty element.
    test('TC-PKW-11 [Boundary]: an empty guide writes a bare element', () {
      final String xml = _build((XmlBuilder b) => const EpubGuideWriter()
          .writeGuide(b, EpubGuide()..Items = <EpubGuideReference>[]));

      expect(xml, '<guide/>');
    });

    // TC-PKW-12 [Error guessing]: `title` is optional in the OPF and
    // `PackageReader` only requires `type` and `href`, but the writer
    // dereferences all three — a titleless reference throws.
    test('TC-PKW-12 [Error guessing]: a reference with no title throws', () {
      expect(
          () => _build((XmlBuilder b) => const EpubGuideWriter().writeGuide(
              b,
              EpubGuide()
                ..Items = <EpubGuideReference>[
                  EpubGuideReference()
                    ..Type = 'toc'
                    ..Href = 'chapter1.xhtml',
                ])),
          throwsA(isA<TypeError>()));
    });

    // TC-PKW-13 [Error guessing]: and a null guide — what the reader produces
    // for an OPF with no `<guide>` at all — throws too. This is the failure
    // `EpubWriter` inherits; see TC-WRT-7.
    test('TC-PKW-13 [Error guessing]: a null guide is not tolerated', () {
      expect(
          () => _build(
              (XmlBuilder b) => const EpubGuideWriter().writeGuide(b, null)),
          throwsA(isA<TypeError>()));
    });
  });

  group('const EpubPackageWriter().writeContent', () {
    // TC-PKW-14 [Equivalence partitioning]: the version attribute is the one
    // thing the package element decides, and the ternary has no third arm —
    // anything that is not EPUB2 is written as 3.0.
    for (final List<Object?> row in <List<Object?>>[
      <Object?>[EpubVersion.Epub2, '2.0'],
      <Object?>[EpubVersion.Epub3, '3.0'],
      <Object?>[null, '3.0'],
    ]) {
      test('TC-PKW-14 [Equivalence]: version ${row[0]} writes ${row[1]}', () {
        final String xml = const EpubPackageWriter()
            .writeContent(_minimalPackage(row[0] as EpubVersion?));

        expect(xml, contains('version="${row[1]}"'));
      });
    }

    // TC-PKW-15 [Scenario/use-case]: the four sections are emitted in OPF
    // order, inside the package namespace, under an XML declaration.
    test(
        'TC-PKW-15 [Scenario]: emits metadata, manifest, spine and guide in '
        'order', () {
      final String xml = const EpubPackageWriter()
          .writeContent(_minimalPackage(EpubVersion.Epub2));

      final XmlElement package = XmlDocument.parse(xml).rootElement;
      expect(xml, startsWith('<?xml version="1.0"?>'));
      expect(package.name.local, 'package');
      expect(package.getAttribute('xmlns'), 'http://www.idpf.org/2007/opf');
      expect(package.getAttribute('unique-identifier'), 'etextno');
      expect(package.childElements.map((XmlElement e) => e.name.local),
          <String>['metadata', 'manifest', 'spine', 'guide']);
    });

    // TC-PKW-16 [Scenario/use-case]: the metadata writer really is wired in —
    // a title and a meta item set on the package reach the output.
    test('TC-PKW-16 [Scenario]: package metadata reaches the document', () {
      final EpubPackage package = _minimalPackage(EpubVersion.Epub2);
      package.Metadata!.MetaItems = <EpubMetadataMeta>[
        EpubMetadataMeta()
          ..Name = 'cover'
          ..Content = 'cover-image',
      ];

      final String xml = const EpubPackageWriter().writeContent(package);

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
      final EpubPackage package = _minimalPackage(EpubVersion.Epub2);
      package.Metadata!.Identifiers = <EpubMetadataIdentifier>[
        EpubMetadataIdentifier()
          ..Id = 'NGE-SEED-uuid'
          ..Identifier = 'NGE-SEED-ID',
      ];

      final String xml = const EpubPackageWriter().writeContent(package);

      expect(xml, contains('unique-identifier="etextno"'));
      expect(xml, contains('<dc:identifier id="NGE-SEED-uuid">'));
    });
  });
}
