// The shapes an EPUB3 nav document can take inside its `<ol>`: nested lists,
// `<span>` group headings with no link, and entries the parser refuses.
//
// The sibling file `navigation_reader_epub3_nav_path_test.dart` covers where
// the nav document sits in the archive; this one covers what is inside it.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

const String _opfEpub3 = '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="uid">urn:uuid:NGE-SEED-NAV3-CONTENT</dc:identifier>'
    '<dc:title>NGE-SEED Nav3 Content</dc:title>'
    '</metadata>'
    '<manifest>'
    '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
    'properties="nav"/>'
    '<item id="ch1" href="chapter1.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '<item id="ch2" href="chapter2.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '</manifest>'
    '<spine><itemref idref="ch1"/><itemref idref="ch2"/></spine>'
    '</package>';

String _navDocument(String listItems) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml" '
    'xmlns:epub="http://www.idpf.org/2007/ops">'
    '<head><title>NGE-SEED Navigation</title></head>'
    '<body><nav epub:type="toc"><ol>$listItems</ol></nav></body>'
    '</html>';

Uint8List _epub3With(String listItems) => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': _opfEpub3,
        'OEBPS/nav.xhtml': _navDocument(listItems),
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
        'OEBPS/chapter2.xhtml': seedXhtml('NGE-SEED-CH2'),
      },
    );

void main() {
  group('NavigationReader EPUB3 nav document contents', () {
    // TC-NAV3-1 [Scenario/use-case]: a nested `<ol>` becomes child navigation
    // points, and the docTitle is taken from the package metadata rather than
    // the nav document.
    test(
      'TC-NAV3-1 [Scenario]: a nested ol becomes child navigation points',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _epub3With(
            '<li><a href="chapter1.xhtml">NGE-SEED Chapter One</a>'
            '<ol><li><a href="chapter1.xhtml#sec-1">NGE-SEED Section 1</a>'
            '</li></ol></li>'
            '<li><a href="chapter2.xhtml">NGE-SEED Chapter Two</a></li>',
          ),
        );

        final EpubNavigation navigation = bookRef.schema!.navigation!;
        expect(navigation.docTitle!.titles, <String>['NGE-SEED Nav3 Content']);
        expect(navigation.docAuthors, isEmpty);
        expect(navigation.navMap!.points, hasLength(2));

        final EpubNavigationPoint first = navigation.navMap!.points!.first;
        expect(first.navigationLabels!.single.text, 'NGE-SEED Chapter One');
        expect(first.childNavigationPoints, hasLength(1));
        expect(
          first.childNavigationPoints!.single.content!.source,
          'chapter1.xhtml#sec-1',
        );

        final List<EpubChapterRef> chapters = await bookRef.getChapters();
        expect(chapters, hasLength(2));
        expect(chapters.first.subChapters!.single.anchor, 'sec-1');
      },
    );

    // TC-NAV3-2 [Equivalence partitioning]: a `<span>` heading is a label
    // with no href, so its content source stays null and ChapterReader drops
    // that entry (with its children) instead of failing the open.
    test(
      'TC-NAV3-2 [Equivalence partitioning]: a span entry yields a sourceless '
      'navigation point that produces no chapter',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _epub3With(
            '<li><span>NGE-SEED Part One</span>'
            '<ol><li><a href="chapter1.xhtml">NGE-SEED Chapter One</a></li>'
            '</ol></li>'
            '<li><a href="chapter2.xhtml">NGE-SEED Chapter Two</a></li>',
          ),
        );

        final EpubNavigationPoint span =
            bookRef.schema!.navigation!.navMap!.points!.first;
        expect(span.navigationLabels!.single.text, 'NGE-SEED Part One');
        expect(span.content, isNotNull);
        expect(span.content!.source, isNull);

        final List<EpubChapterRef> chapters = await bookRef.getChapters();
        expect(chapters, hasLength(1));
        expect(chapters.single.contentFileName, 'chapter2.xhtml');
      },
    );

    // TC-NAV3-3 [Error guessing]: an `<li>` with neither `<a>` nor `<span>`
    // has no label, which the parser refuses.
    test(
      'TC-NAV3-3 [Error guessing]: an li with no anchor or span is rejected',
      () {
        expect(
          () => const EpubReader().openBook(
            _epub3With('<li><p>NGE-SEED orphan text</p></li>'),
          ),
          throwsA(
            isA<Exception>().having(
              (Exception e) => e.toString(),
              'message',
              contains('at least one navigation label'),
            ),
          ),
        );
      },
    );

    // TC-NAV3-4 [Equivalence partitioning]: children of the nav `<ol>` that
    // are not `<li>` are skipped rather than parsed.
    test(
      'TC-NAV3-4 [Equivalence partitioning]: non-li children of the nav ol '
      'are skipped',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _epub3With(
            '<div>NGE-SEED stray</div>'
            '<li><a href="chapter1.xhtml">NGE-SEED Chapter One</a></li>',
          ),
        );

        expect(bookRef.schema!.navigation!.navMap!.points, hasLength(1));
      },
    );

    // TC-NAV3-5 [Scenario/use-case]: an id on the nav anchor is carried into
    // the navigation content alongside the resolved href.
    test(
      'TC-NAV3-5 [Scenario]: the anchor id is read into the navigation '
      'content',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _epub3With(
            '<li><a id="toc-1" href="chapter1.xhtml">NGE-SEED Chapter One</a>'
            '</li>',
          ),
        );

        final EpubNavigationPoint point =
            bookRef.schema!.navigation!.navMap!.points!.single;
        expect(point.content!.id, 'toc-1');
        expect(point.content!.source, 'chapter1.xhtml');
      },
    );
  });
}
