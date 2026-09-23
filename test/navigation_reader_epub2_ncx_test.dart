// `NavigationReader`'s EPUB2 (NCX) branch, end to end through
// `EpubReader.openBook` — the branch the EPUB3 suite never enters.
//
// One rich NCX exercises the whole walk in a single open: head/meta,
// docTitle, repeated docAuthor, a nested navMap, a pageList of pageTargets
// and a navList. The per-element error paths live in
// `navigation_reader_element_test.dart`; archive-shaped failures live in
// `navigation_reader_archive_errors_test.dart`.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_list.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target_type.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_target.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

const String _ncxWithEveryNavigationElement =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head>'
    '<meta name="dtb:uid" content="urn:uuid:NGE-SEED-EPUB2-NCX"/>'
    '<meta name="dtb:depth" content="2" scheme="NGE-SEED-SCHEME"/>'
    '</head>'
    '<docTitle><text>NGE-SEED NCX Doc Title</text></docTitle>'
    '<docAuthor><text>NGE-SEED Author One</text></docAuthor>'
    '<docAuthor><text>NGE-SEED Author Two</text></docAuthor>'
    '<navMap>'
    '<navPoint id="np-1" class="chapter" playOrder="1">'
    '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
    '<content src="chapter1.xhtml"/>'
    '<navPoint id="np-1-1" playOrder="2">'
    '<navLabel><text>NGE-SEED Section 1.1</text></navLabel>'
    '<content id="c-1-1" src="chapter1.xhtml#sec-1-1"/>'
    '</navPoint>'
    '</navPoint>'
    '<navPoint id="np-2" playOrder="3">'
    '<navLabel><text>NGE-SEED Chapter Two</text></navLabel>'
    '<content src="chapter2.xhtml"/>'
    '</navPoint>'
    '</navMap>'
    '<pageList>'
    '<pageTarget id="pt-1" value="1" type="normal" class="pagenum" '
    'playOrder="4">'
    '<navLabel><text>1</text></navLabel>'
    '<content id="c-pt-1" src="chapter1.xhtml#page-1"/>'
    '</pageTarget>'
    '<pageTarget id="pt-2" value="i" type="front">'
    '<navLabel><text>i</text></navLabel>'
    '<content src="chapter1.xhtml#page-i"/>'
    '</pageTarget>'
    '<notAPageTarget/>'
    '</pageList>'
    '</ncx>';

const String _opfEpub2 = '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
    'unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="uid">urn:uuid:NGE-SEED-EPUB2-NCX</dc:identifier>'
    '<dc:title>NGE-SEED EPUB2 NCX Book</dc:title>'
    '<dc:language>en</dc:language>'
    '</metadata>'
    '<manifest>'
    '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
    '<item id="ch1" href="chapter1.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '<item id="ch2" href="chapter2.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '</manifest>'
    '<spine toc="ncx">'
    '<itemref idref="ch1"/>'
    '<itemref idref="ch2"/>'
    '</spine>'
    '</package>';

/// The book above with its NCX replaced by [ncx], and its OPF by [opf];
/// [ncxPath] is where the NCX sits in the archive.
Uint8List _buildEpub2Book({
  String ncx = _ncxWithEveryNavigationElement,
  String opf = _opfEpub2,
  String ncxPath = 'OEBPS/toc.ncx',
}) =>
    buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': opf,
        ncxPath: ncx,
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
        'OEBPS/chapter2.xhtml': seedXhtml('NGE-SEED-CH2'),
      },
    );

/// The rich NCX with [navLists] appended after its pageList.
String _ncxWithNavLists(String navLists) =>
    _ncxWithEveryNavigationElement.replaceFirst('</ncx>', '$navLists</ncx>');

List<String> _labelTexts(List<EpubNavigationLabel> labels) =>
    labels.map((EpubNavigationLabel label) => label.text).toList();

void main() {
  group('NavigationReader EPUB2 NCX branch', () {
    // TC-NCX-1 [Scenario/use-case]: a complete NCX produces every navigation
    // sub-structure in one open — head meta, docTitle, docAuthors, navMap.
    test(
      'TC-NCX-1 [Scenario]: complete NCX populates head, docTitle, docAuthors '
      'and navMap',
      () async {
        final EpubBookRef bookRef =
            await const EpubReader().openBook(_buildEpub2Book());
        final EpubNavigation navigation = bookRef.schema.navigation;

        final List<EpubNavigationHeadMeta> meta = navigation.head.metadata;
        expect(meta, hasLength(2));
        expect(meta[0].name, 'dtb:uid');
        expect(meta[0].content, 'urn:uuid:NGE-SEED-EPUB2-NCX');
        expect(meta[0].scheme, isNull);
        expect(meta[1].name, 'dtb:depth');
        expect(meta[1].content, '2');
        expect(meta[1].scheme, 'NGE-SEED-SCHEME');

        expect(navigation.docTitle.titles, <String>['NGE-SEED NCX Doc Title']);
        expect(
          navigation.docAuthors
              .map((EpubNavigationDocAuthor a) => a.authors.single),
          <String>['NGE-SEED Author One', 'NGE-SEED Author Two'],
        );
        expect(navigation.navMap.points, hasLength(2));
        expect(navigation.pageList, isNotNull);
        expect(navigation.navLists, isEmpty);
      },
    );

    // TC-NCX-2 [Scenario/use-case]: navPoint attributes and one level of
    // nesting survive the walk, including the `#anchor` split performed
    // downstream by ChapterReader.
    test(
      'TC-NCX-2 [Scenario]: nested navPoints keep id/class/playOrder and '
      'resolve to chapters with anchors split off',
      () async {
        final EpubBookRef bookRef =
            await const EpubReader().openBook(_buildEpub2Book());
        final List<EpubNavigationPoint> points =
            bookRef.schema.navigation.navMap.points;
        final EpubNavigationPoint first = points.first;

        expect(first.id, 'np-1');
        expect(first.className, 'chapter');
        expect(first.playOrder, '1');
        expect(_labelTexts(first.navigationLabels),
            <String>['NGE-SEED Chapter One']);
        expect(first.content.id, isNull);
        expect(first.content.source, 'chapter1.xhtml');

        final EpubNavigationPoint nested = first.childNavigationPoints.single;
        expect(nested.id, 'np-1-1');
        expect(nested.className, isNull);
        expect(nested.playOrder, '2');
        expect(_labelTexts(nested.navigationLabels),
            <String>['NGE-SEED Section 1.1']);
        expect(nested.content.id, 'c-1-1');
        expect(nested.content.source, 'chapter1.xhtml#sec-1-1');
        expect(nested.childNavigationPoints, isEmpty);

        expect(points[1].id, 'np-2');
        expect(points[1].playOrder, '3');
        expect(points[1].childNavigationPoints, isEmpty);

        final List<EpubChapterRef> chapters = await bookRef.getChapters();
        expect(chapters, hasLength(2));
        expect(chapters[0].title, 'NGE-SEED Chapter One');
        expect(chapters[0].anchor, isNull);
        expect(chapters[0].subChapters.single.anchor, 'sec-1-1');
        expect(chapters[1].contentFileName, 'chapter2.xhtml');
      },
    );

    // TC-NCX-3 [Scenario/use-case]: pageList targets are read with their type
    // enum resolved, and a non-`pageTarget` sibling is skipped. The second
    // target has no `class` or `playOrder`: class reads null, and playOrder,
    // which NCX requires, reads ''.
    test(
      'TC-NCX-3 [Scenario]: pageList reads pageTargets with typed values and '
      'skips foreign children',
      () async {
        final EpubBookRef bookRef =
            await const EpubReader().openBook(_buildEpub2Book());
        final List<EpubNavigationPageTarget> targets =
            bookRef.schema.navigation.pageList!.targets;

        expect(targets, hasLength(2));
        expect(targets[0].id, 'pt-1');
        expect(targets[0].value, '1');
        expect(targets[0].className, 'pagenum');
        expect(targets[0].playOrder, '4');
        expect(targets[0].type, EpubNavigationPageTargetType.normal);
        expect(_labelTexts(targets[0].navigationLabels), <String>['1']);
        expect(targets[0].content.id, 'c-pt-1');
        expect(targets[0].content.source, 'chapter1.xhtml#page-1');

        expect(targets[1].id, 'pt-2');
        expect(targets[1].value, 'i');
        expect(targets[1].className, isNull);
        expect(targets[1].playOrder, '');
        expect(targets[1].type, EpubNavigationPageTargetType.front);
        expect(_labelTexts(targets[1].navigationLabels), <String>['i']);
        expect(targets[1].content.id, isNull);
        expect(targets[1].content.source, 'chapter1.xhtml#page-i');
      },
    );

    // TC-NCX-4 [Equivalence partitioning]: an NCX with no pageList leaves
    // pageList null rather than an empty structure — the other side of the
    // optional-pageList branch covered by TC-NCX-3.
    test(
      'TC-NCX-4 [Equivalence partitioning]: NCX without a pageList leaves '
      'pageList null and still lists navLists empty',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildEpub2Book(
            ncx: _ncxWithEveryNavigationElement.replaceFirst(
              RegExp(r'<pageList>.*</pageList>'),
              '',
            ),
          ),
        );

        expect(bookRef.schema.navigation.pageList, isNull);
        expect(bookRef.schema.navigation.navLists, isEmpty);
      },
    );

    // TC-NCX-6 [Boundary value]: a childless navList is collected with both
    // of its lists empty — NCX requires a label and a target, but nothing
    // downstream reads nav lists, so the book still opens.
    test(
      'TC-NCX-6 [Boundary]: childless navList is collected into navLists',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildEpub2Book(
            ncx: _ncxWithNavLists('<navList id="nl-1" class="illustrations"/>'),
          ),
        );

        final List<EpubNavigationList> navLists =
            bookRef.schema.navigation.navLists;
        expect(navLists, hasLength(1));
        expect(navLists.single.id, 'nl-1');
        expect(navLists.single.className, 'illustrations');
        expect(navLists.single.navigationLabels, isEmpty);
        expect(navLists.single.navigationTargets, isEmpty);
      },
    );

    // TC-NCX-5 [Scenario/use-case]: navLists carrying a navLabel and
    // navTargets are read in document order, every navTarget field included;
    // a target with no playOrder or content reads '' and a sourceless
    // content.
    test(
      'TC-NCX-5 [Scenario]: navList with a navLabel and navTargets is read '
      'on open',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildEpub2Book(
            ncx: _ncxWithNavLists(
              '<navList id="nl-1" class="illustrations">'
              '<navLabel><text>NGE-SEED Illustrations</text></navLabel>'
              '<navTarget id="nt-1" value="fig-1" class="figure" '
              'playOrder="5">'
              '<navLabel><text>NGE-SEED Figure 1</text></navLabel>'
              '<content id="c-nt-1" src="chapter1.xhtml#fig-1"/>'
              '</navTarget>'
              '<navTarget id="nt-2">'
              '<navLabel><text>NGE-SEED Figure 2</text></navLabel>'
              '</navTarget>'
              '</navList>'
              '<navList id="nl-2">'
              '<navLabel><text>NGE-SEED Tables</text></navLabel>'
              '</navList>',
            ),
          ),
        );

        final List<EpubNavigationList> navLists =
            bookRef.schema.navigation.navLists;
        expect(navLists, hasLength(2));

        final EpubNavigationList illustrations = navLists[0];
        expect(illustrations.id, 'nl-1');
        expect(illustrations.className, 'illustrations');
        expect(_labelTexts(illustrations.navigationLabels),
            <String>['NGE-SEED Illustrations']);
        expect(illustrations.navigationTargets, hasLength(2));

        final EpubNavigationTarget figure1 = illustrations.navigationTargets[0];
        expect(figure1.id, 'nt-1');
        expect(figure1.value, 'fig-1');
        expect(figure1.className, 'figure');
        expect(figure1.playOrder, '5');
        expect(_labelTexts(figure1.navigationLabels),
            <String>['NGE-SEED Figure 1']);
        expect(figure1.content.id, 'c-nt-1');
        expect(figure1.content.source, 'chapter1.xhtml#fig-1');

        final EpubNavigationTarget figure2 = illustrations.navigationTargets[1];
        expect(figure2.id, 'nt-2');
        expect(figure2.value, isNull);
        expect(figure2.className, isNull);
        expect(figure2.playOrder, '');
        expect(_labelTexts(figure2.navigationLabels),
            <String>['NGE-SEED Figure 2']);
        expect(figure2.content.id, isNull);
        expect(figure2.content.source, isNull);

        final EpubNavigationList tables = navLists[1];
        expect(tables.id, 'nl-2');
        expect(tables.className, isNull);
        expect(
            _labelTexts(tables.navigationLabels), <String>['NGE-SEED Tables']);
        expect(tables.navigationTargets, isEmpty);
      },
    );

    // TC-NCX-7 [Equivalence partitioning]: the NCX's manifest href is a URL,
    // so it may escape its file name; the archive entry is found under the
    // decoded name.
    test(
      'TC-NCX-7 [Equivalence partitioning]: a percent-encoded NCX href finds '
      'the NCX under its decoded name',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildEpub2Book(
            opf: _opfEpub2.replaceFirst(
                'href="toc.ncx"', 'href="NGE-SEED%20t%C3%B6c.ncx"'),
            ncxPath: 'OEBPS/NGE-SEED töc.ncx',
          ),
        );

        expect(bookRef.schema.navigation.docTitle.titles,
            <String>['NGE-SEED NCX Doc Title']);
      },
    );

    // TC-NCX-8 [Equivalence partitioning]: the spine's `toc` id and the NCX
    // entry name are both matched ignoring case, since books disagree with
    // their own manifests on case.
    test(
      'TC-NCX-8 [Equivalence partitioning]: toc id and NCX entry name are '
      'matched ignoring case',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildEpub2Book(
            opf: _opfEpub2.replaceFirst(
                '<spine toc="ncx">', '<spine toc="NCX">'),
            ncxPath: 'OEBPS/TOC.NCX',
          ),
        );

        expect(bookRef.schema.navigation.docTitle.titles,
            <String>['NGE-SEED NCX Doc Title']);
      },
    );
  });
}
