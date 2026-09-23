// `EpubNavigationWriter` — the NCX serialiser.
//
// Unlike the other writers this one has no caller: `EpubWriter` carries the
// NCX through as a raw content file and never regenerates it, and nothing else
// in the package references this class. So the tests here are the only thing
// executing it, and the one that matters most is TC-NVW-5: the NCX it produces
// is fed back through `NavigationReader` to show the output is a document this
// package can actually read.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/writers/epub_navigation_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/epub_fixture.dart';

/// A navigation point linking to [source]; a null [source] is the shape an
/// EPUB3 `<span>` heading reads as — an entry that links nowhere.
EpubNavigationPoint _point(
  String id,
  String playOrder,
  String label,
  String? source, {
  List<EpubNavigationPoint> children = const <EpubNavigationPoint>[],
}) =>
    EpubNavigationPoint(
      id: id,
      playOrder: playOrder,
      navigationLabels: <EpubNavigationLabel>[EpubNavigationLabel(text: label)],
      content: EpubNavigationContent(source: source),
      childNavigationPoints: children,
    );

EpubNavigation _navigation(
  List<EpubNavigationPoint> points, {
  List<String> titles = const <String>['NGE-SEED Navigation'],
  List<EpubNavigationHeadMeta> headMetadata = const <EpubNavigationHeadMeta>[
    EpubNavigationHeadMeta(name: 'dtb:uid', content: 'NGE-SEED-ID'),
  ],
}) =>
    EpubNavigation(
      head: EpubNavigationHead(metadata: headMetadata),
      docTitle: EpubNavigationDocTitle(titles: titles),
      navMap: EpubNavigationMap(points: points),
    );

/// Runs [write] against a fresh builder and returns the document it produced.
String _build(void Function(XmlBuilder builder) write) {
  final XmlBuilder builder = XmlBuilder();
  write(builder);
  return builder.buildDocument().toXmlString();
}

/// Wraps [ncx] in an EPUB2 archive whose spine points at it, so
/// `EpubReader.readBook` parses it through the production navigation path.
Uint8List _archiveAround(String ncx) => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
            'unique-identifier="etextno">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:title>NGE-SEED Navigation</dc:title>'
            '</metadata>'
            '<manifest>'
            '<item id="ncx" href="toc.ncx" '
            'media-type="application/x-dtbncx+xml"/>'
            '<item id="ch1" href="chapter1.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine toc="ncx"><itemref idref="ch1"/></spine>'
            '</package>',
        'OEBPS/toc.ncx': ncx,
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED Chapter One'),
      },
    );

void main() {
  group('EpubNavigationWriter.writeNavigation', () {
    // TC-NVW-1 [Scenario/use-case]: the whole document — declaration, root
    // attributes, namespace, and the three sections in NCX order.
    test('TC-NVW-1 [Scenario]: writes a complete NCX document', () {
      final String ncx = const EpubNavigationWriter()
          .writeNavigation(_navigation(<EpubNavigationPoint>[
        _point('np-1', '1', 'NGE-SEED Chapter One', 'chapter1.xhtml'),
      ]));

      expect(ncx, startsWith('<?xml version="1.0"?>'));
      final XmlElement root = XmlDocument.parse(ncx).rootElement;
      expect(root.name.local, 'ncx');
      expect(root.getAttribute('version'), '2005-1');
      expect(root.getAttribute('lang'), 'en');
      expect(
          root.getAttribute('xmlns'), 'http://www.daisy.org/z3986/2005/ncx/');
      expect(root.childElements.map((XmlElement e) => e.name.local),
          <String>['head', 'docTitle', 'navMap']);
    });

    // TC-NVW-2 [Scenario/use-case]: the head's meta items, which is where the
    // NCX carries the book's uid.
    test('TC-NVW-2 [Scenario]: head meta items write content and name', () {
      final String ncx = const EpubNavigationWriter()
          .writeNavigation(_navigation(<EpubNavigationPoint>[]));

      expect(
          ncx,
          contains(
              '<head><meta content="NGE-SEED-ID" name="dtb:uid"/></head>'));
      expect(ncx, contains('<docTitle>NGE-SEED Navigation</docTitle>'));
    });

    // TC-NVW-3 [Scenario/use-case]: a navPoint's id, play order, label and
    // content src, written once per point and in order.
    test(
        'TC-NVW-3 [Scenario]: each navPoint writes id, playOrder, label and '
        'src', () {
      final String ncx = const EpubNavigationWriter()
          .writeNavigation(_navigation(<EpubNavigationPoint>[
        _point('np-1', '1', 'NGE-SEED Chapter One', 'chapter1.xhtml'),
        _point('np-2', '2', 'NGE-SEED Chapter Two', 'chapter2.xhtml'),
      ]));

      expect(
          ncx,
          contains('<navMap>'
              '<navPoint id="np-1" playOrder="1">'
              '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
              '<content src="chapter1.xhtml"/>'
              '</navPoint>'
              '<navPoint id="np-2" playOrder="2">'
              '<navLabel><text>NGE-SEED Chapter Two</text></navLabel>'
              '<content src="chapter2.xhtml"/>'
              '</navPoint>'
              '</navMap>'));
    });

    // TC-NVW-4 [Boundary value]: an empty navMap and an empty docTitle are
    // both written as empty elements rather than being skipped.
    test('TC-NVW-4 [Boundary]: an empty navigation writes empty sections', () {
      final String ncx = const EpubNavigationWriter().writeNavigation(
          _navigation(<EpubNavigationPoint>[],
              titles: <String>[], headMetadata: <EpubNavigationHeadMeta>[]));

      expect(ncx, contains('<head/>'));
      expect(ncx, contains('<docTitle/>'));
      expect(ncx, contains('<navMap/>'));
    });

    // TC-NVW-8 [Equivalence partitioning]: an entry with no link — an EPUB3
    // `<span>` heading — has no NCX form, since a navPoint must carry a
    // `content` src. It is left out, and the linked entries on either side
    // are written as usual.
    test('TC-NVW-8 [Equivalence]: a navPoint with no source is skipped', () {
      final String ncx = const EpubNavigationWriter()
          .writeNavigation(_navigation(<EpubNavigationPoint>[
        _point('np-1', '1', 'NGE-SEED Chapter One', 'chapter1.xhtml'),
        _point('np-heading', '2', 'NGE-SEED Part Heading', null),
        _point('np-3', '3', 'NGE-SEED Chapter Three', 'chapter3.xhtml'),
      ]));

      expect(ncx, isNot(contains('np-heading')));
      expect(ncx, isNot(contains('NGE-SEED Part Heading')));
      expect(
          XmlDocument.parse(ncx)
              .findAllElements('navPoint')
              .map((XmlElement e) => e.getAttribute('id')),
          <String>['np-1', 'np-3']);
    });
  });

  group('EpubNavigationWriter.writeNavigationPoint', () {
    // TC-NVW-9 [Scenario/use-case]: the src a navPoint links to is the
    // `source` argument, not a second read of the point's own content —
    // `writeNavigationMap` has already resolved it. A point whose content
    // has no source is written with the one it is given.
    <String, String?>{
      'a different own source': 'NGE-SEED-own.xhtml',
      'no own source': null,
    }.forEach((String label, String? ownSource) {
      test('TC-NVW-9 [Scenario]: src comes from the argument, point has $label',
          () {
        final String xml = _build((XmlBuilder b) => const EpubNavigationWriter()
            .writeNavigationPoint(
                b,
                _point('np-1', '1', 'NGE-SEED Chapter One', ownSource),
                'NGE-SEED-given.xhtml'));

        expect(
            xml,
            '<navPoint id="np-1" playOrder="1">'
            '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
            '<content src="NGE-SEED-given.xhtml"/>'
            '</navPoint>');
      });
    });
  });

  group('EpubNavigationWriter.writeNavigation read back', () {
    // TC-NVW-5 [Scenario/use-case]: the output is a real NCX — the head and
    // the navMap parse back into equal entities, and `EpubReader` derives the
    // chapter list from them. The docTitle does NOT survive; TC-NVW-6 is why,
    // and keeping it out of this assertion is what lets this one be exact.
    test(
        'TC-NVW-5 [Scenario]: the written NCX reads back as the same head and '
        'navMap', () async {
      final EpubNavigation original = _navigation(<EpubNavigationPoint>[
        _point('np-1', '1', 'NGE-SEED Chapter One', 'chapter1.xhtml'),
      ]);

      final EpubBook book = await const EpubReader().readBook(_archiveAround(
          const EpubNavigationWriter().writeNavigation(original)));

      expect(book.schema.navigation.head.metadata, original.head.metadata);
      expect(book.schema.navigation.navMap.points, original.navMap.points);
      expect(book.chapters.single.title, 'NGE-SEED Chapter One');
      expect(book.chapters.single.contentFileName, 'chapter1.xhtml');
    });

    // TC-NVW-6 [Error guessing]: `writeNavigationDocTitle` puts the titles
    // straight into the `docTitle` element, but NCX wraps each one in a
    // `<text>` child and `NavigationReader.readNavigationDocTitle` reads only
    // those. A written docTitle therefore always reads back empty — and two
    // titles run together into one text node on the way out.
    test(
        'TC-NVW-6 [Error guessing]: docTitle is written without its text '
        'wrapper and reads back empty', () async {
      final EpubNavigation original = _navigation(<EpubNavigationPoint>[],
          titles: <String>['NGE-SEED One', 'NGE-SEED Two']);

      final String ncx = const EpubNavigationWriter().writeNavigation(original);

      expect(ncx, contains('<docTitle>NGE-SEED OneNGE-SEED Two</docTitle>'));
      final EpubBook book =
          await const EpubReader().readBook(_archiveAround(ncx));
      expect(book.schema.navigation.docTitle.titles, isEmpty);
    });

    // TC-NVW-7 [Error guessing]: `writeNavigationPoint` does not recurse into
    // `childNavigationPoints`, so a nested table of contents is flattened to
    // its top level — the sub-chapters are simply gone.
    test('TC-NVW-7 [Error guessing]: nested navPoints are dropped', () async {
      final EpubNavigation original = _navigation(<EpubNavigationPoint>[
        _point('np-1', '1', 'NGE-SEED Chapter One', 'chapter1.xhtml',
            children: <EpubNavigationPoint>[
              _point('np-1-1', '2', 'NGE-SEED Section One', 'chapter1.xhtml'),
            ]),
      ]);

      final String ncx = const EpubNavigationWriter().writeNavigation(original);

      expect(ncx, isNot(contains('np-1-1')));
      final EpubBook book =
          await const EpubReader().readBook(_archiveAround(ncx));
      expect(book.chapters.single.subChapters, isEmpty);
    });
  });
}
