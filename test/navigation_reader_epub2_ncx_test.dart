// `NavigationReader`'s EPUB2 (NCX) branch, end to end through
// `EpubReader.openBook` — the branch the EPUB3 suite never enters.
//
// One rich NCX exercises the whole walk in a single open: head/meta,
// docTitle, repeated docAuthor, a nested navMap, and a pageList of
// pageTargets. The per-element error paths live in
// `navigation_reader_unit_test.dart`; archive-shaped failures live in
// `navigation_reader_archive_errors_test.dart`.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_list.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation_page_target_type.dart';
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
    '<content src="chapter1.xhtml#page-1"/>'
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

Uint8List _buildEpub2Book() => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': _opfEpub2,
        'OEBPS/toc.ncx': _ncxWithEveryNavigationElement,
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
        'OEBPS/chapter2.xhtml': seedXhtml('NGE-SEED-CH2'),
      },
    );

/// An NCX whose `navList` carries a `navLabel`. `EpubNavigationList` leaves
/// `NavigationLabels` null and `NavigationReader.readNavigationList` adds to
/// it through `!` — see TC-NCX-5.
const String _ncxWithNavList = '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-NAVLIST"/></head>'
    '<docTitle><text>NGE-SEED NavList Book</text></docTitle>'
    '<navMap>'
    '<navPoint id="np-1" playOrder="1">'
    '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
    '<content src="chapter1.xhtml"/>'
    '</navPoint>'
    '</navMap>'
    '<navList id="nl-1" class="illustrations">'
    '<navLabel><text>NGE-SEED Illustrations</text></navLabel>'
    '</navList>'
    '</ncx>';

Uint8List _buildEpub2BookWithNavList() => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': _opfEpub2.replaceFirst(
          '<item id="ch2" href="chapter2.xhtml" '
              'media-type="application/xhtml+xml"/>',
          '',
        ),
        'OEBPS/toc.ncx': _ncxWithNavList,
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
      },
    );

void main() {
  group('NavigationReader EPUB2 NCX branch', () {
    // TC-NCX-1 [Scenario/use-case]: a complete NCX produces every navigation
    // sub-structure in one open — head meta, docTitle, docAuthors, navMap.
    test(
      'TC-NCX-1 [Scenario]: complete NCX populates head, docTitle, docAuthors '
      'and navMap',
      () async {
        final EpubBookRef bookRef =
            await EpubReader.openBook(_buildEpub2Book());
        final EpubNavigation navigation = bookRef.Schema!.Navigation!;

        final List<EpubNavigationHeadMeta> meta = navigation.Head!.Metadata!;
        expect(meta, hasLength(2));
        expect(meta[0].Name, 'dtb:uid');
        expect(meta[0].Content, 'urn:uuid:NGE-SEED-EPUB2-NCX');
        expect(meta[1].Scheme, 'NGE-SEED-SCHEME');

        expect(navigation.DocTitle!.Titles, <String>['NGE-SEED NCX Doc Title']);
        expect(
          navigation.DocAuthors!
              .map((EpubNavigationDocAuthor a) => a.Authors!.single),
          <String>['NGE-SEED Author One', 'NGE-SEED Author Two'],
        );
        expect(navigation.NavMap!.Points, hasLength(2));
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
            await EpubReader.openBook(_buildEpub2Book());
        final EpubNavigationPoint first =
            bookRef.Schema!.Navigation!.NavMap!.Points!.first;

        expect(first.Id, 'np-1');
        expect(first.Class, 'chapter');
        expect(first.PlayOrder, '1');
        expect(first.NavigationLabels!.single.Text, 'NGE-SEED Chapter One');
        expect(first.Content!.Source, 'chapter1.xhtml');
        expect(first.ChildNavigationPoints!.single.Content!.Id, 'c-1-1');

        final List<EpubChapterRef> chapters = await bookRef.getChapters();
        expect(chapters, hasLength(2));
        expect(chapters[0].Title, 'NGE-SEED Chapter One');
        expect(chapters[0].Anchor, isNull);
        expect(chapters[0].SubChapters!.single.Anchor, 'sec-1-1');
        expect(chapters[1].ContentFileName, 'chapter2.xhtml');
      },
    );

    // TC-NCX-3 [Scenario/use-case]: pageList targets are read with their type
    // enum resolved, and a non-`pageTarget` sibling is skipped.
    test(
      'TC-NCX-3 [Scenario]: pageList reads pageTargets with typed values and '
      'skips foreign children',
      () async {
        final EpubBookRef bookRef =
            await EpubReader.openBook(_buildEpub2Book());
        final List<EpubNavigationPageTarget> targets =
            bookRef.Schema!.Navigation!.PageList!.Targets!;

        expect(targets, hasLength(2));
        expect(targets[0].Id, 'pt-1');
        expect(targets[0].Value, '1');
        expect(targets[0].Class, 'pagenum');
        expect(targets[0].PlayOrder, '4');
        expect(targets[0].Type, EpubNavigationPageTargetType.NORMAL);
        expect(targets[0].NavigationLabels!.single.Text, '1');
        expect(targets[0].Content!.Source, 'chapter1.xhtml#page-1');
        expect(targets[1].Type, EpubNavigationPageTargetType.FRONT);
      },
    );

    // TC-NCX-4 [Equivalence partitioning]: an NCX with no pageList leaves
    // PageList null rather than an empty structure — the other side of the
    // optional-pageList branch covered by TC-NCX-3.
    test(
      'TC-NCX-4 [Equivalence partitioning]: NCX without a pageList leaves '
      'PageList null and still lists NavLists empty',
      () async {
        final Uint8List bytes = buildEpubArchive(
          opfPath: 'OEBPS/content.opf',
          textEntries: <String, String>{
            'OEBPS/content.opf': _opfEpub2,
            'OEBPS/toc.ncx': _ncxWithEveryNavigationElement.replaceFirst(
              RegExp(r'<pageList>.*</pageList>'),
              '',
            ),
            'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
            'OEBPS/chapter2.xhtml': seedXhtml('NGE-SEED-CH2'),
          },
        );

        final EpubBookRef bookRef = await EpubReader.openBook(bytes);

        expect(bookRef.Schema!.Navigation!.PageList, isNull);
        expect(bookRef.Schema!.Navigation!.NavLists, isEmpty);
      },
    );

    // TC-NCX-6 [Boundary value]: a childless navList is the one navList shape
    // that survives the walk (TC-NCX-5 covers the other side), so it is the
    // only way NavLists is ever populated.
    test(
      'TC-NCX-6 [Boundary]: childless navList is collected into NavLists',
      () async {
        final Uint8List bytes = buildEpubArchive(
          opfPath: 'OEBPS/content.opf',
          textEntries: <String, String>{
            'OEBPS/content.opf': _opfEpub2,
            'OEBPS/toc.ncx': _ncxWithEveryNavigationElement.replaceFirst(
              '</ncx>',
              '<navList id="nl-1" class="illustrations"/></ncx>',
            ),
            'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
            'OEBPS/chapter2.xhtml': seedXhtml('NGE-SEED-CH2'),
          },
        );

        final EpubBookRef bookRef = await EpubReader.openBook(bytes);

        final List<EpubNavigationList> navLists =
            bookRef.Schema!.Navigation!.NavLists!;
        expect(navLists, hasLength(1));
        expect(navLists.single.Id, 'nl-1');
        expect(navLists.single.Class, 'illustrations');
      },
    );

    // TC-NCX-5 [Error guessing]: KNOWN DEFECT, pinned rather than fixed. An
    // NCX `navList` with a `navLabel` aborts the whole open with a null-check
    // TypeError, because `EpubNavigationList.NavigationLabels` is never
    // initialised while `readNavigationList` appends through `!`. Reported to
    // the caller; the fix belongs in lib/, which this suite must not touch.
    test(
      'TC-NCX-5 [Error guessing]: navList with a navLabel throws TypeError '
      'on open (uninitialised NavigationLabels)',
      () {
        expect(
          () => EpubReader.openBook(_buildEpub2BookWithNavList()),
          throwsA(isA<TypeError>()),
        );
      },
    );
  });
}
