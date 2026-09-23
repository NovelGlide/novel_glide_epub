// `ChapterReader` — turns the navigation map into the chapter-ref tree.
//
// Every case runs through `EpubReader.openBook` and `getChapters()`, which is
// what a real caller uses, on a synthetic book built for the one rule it
// pins: how a navigation link is resolved against the content map (decoded,
// in one lookup, with the anchor split off first), which navigation entries
// yield no chapter, how a `_split_` family is gathered, and the guard for a
// link to a file the manifest never declared.
//
// The content map is keyed by DECODED file name, and the link is decoded the
// same way, so a manifest and a navigation that spell one file differently —
// one escaping `%E7%AC%AC…`, the other writing `第…` raw — still meet.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_text_content_file_ref.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

/// `第一章.xhtml` percent-encoded, as a URL-minded producer writes it.
const String _escapedChapter = '%E7%AC%AC%E4%B8%80%E7%AB%A0.xhtml';

/// The same name written raw, as most CJK books write it; also the archive
/// entry's name and the decoded key.
const String _rawChapter = '第一章.xhtml';

String _opf({required String manifestItems, required String spineItems}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
    'unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>NGE-SEED Chapter Reader Book</dc:title>'
    '</metadata>'
    '<manifest>$manifestItems</manifest>'
    '<spine toc="ncx">$spineItems</spine>'
    '</package>';

String _ncx(String navPoints) => '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-CHR"/></head>'
    '<docTitle><text>NGE-SEED Chapter Reader Book</text></docTitle>'
    '<navMap>$navPoints</navMap>'
    '</ncx>';

const String _ncxItem = '<item id="ncx" href="toc.ncx" '
    'media-type="application/x-dtbncx+xml"/>';

/// An EPUB2 book whose one chapter, archived as `OEBPS/第一章.xhtml`, the
/// manifest spells [manifestHref] and the NCX links as [ncxSrc].
Uint8List _buildEpub2Book({
  required String manifestHref,
  required String ncxSrc,
}) =>
    buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': _opf(
          manifestItems: '$_ncxItem'
              '<item id="ch1" href="$manifestHref" '
              'media-type="application/xhtml+xml"/>',
          spineItems: '<itemref idref="ch1"/>',
        ),
        'OEBPS/toc.ncx': _ncx(
          '<navPoint id="np-1" playOrder="1">'
          '<navLabel><text>NGE-SEED 第一章</text></navLabel>'
          '<content src="$ncxSrc"/>'
          '</navPoint>',
        ),
        'OEBPS/$_rawChapter': seedXhtml('NGE-SEED-CJK-CH1'),
      },
    );

/// An EPUB3 book whose chapter, archived as `OEBPS/第一章.xhtml`, the
/// manifest spells [manifestHref]; [navItems] is the nav document's `<ol>`.
Uint8List _buildEpub3Book({
  required String manifestHref,
  required String navItems,
}) =>
    buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:NGE-SEED-CHR3</dc:identifier>'
            '<dc:title>NGE-SEED Chapter Reader Nav Book</dc:title>'
            '</metadata>'
            '<manifest>'
            '<item id="nav" properties="nav" href="nav.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<item id="ch1" href="$manifestHref" '
            'media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine><itemref idref="ch1"/></spine>'
            '</package>',
        'OEBPS/nav.xhtml': '<?xml version="1.0" encoding="UTF-8"?>'
            '<html xmlns="http://www.w3.org/1999/xhtml" '
            'xmlns:epub="http://www.idpf.org/2007/ops">'
            '<head><title>NGE-SEED Nav</title></head>'
            '<body><nav epub:type="toc"><ol>$navItems</ol></nav></body>'
            '</html>',
        'OEBPS/$_rawChapter': seedXhtml('NGE-SEED-CJK3-CH1'),
      },
    );

Matcher _throwsMessageContaining(String fragment) => throwsA(
      isA<Exception>().having(
        (Exception e) => e.toString(),
        'message',
        contains(fragment),
      ),
    );

void main() {
  group('ChapterReader.getChapters', () {
    // TC-CHR-1 [Equivalence partitioning]: an EPUB3 nav entry that is a
    // `<span>` heading rather than a link has no content source — legal in a
    // nav document — so it yields no chapter, while the linked entry beside
    // it does.
    test(
        'TC-CHR-1 [Equivalence partitioning]: a nav entry with no link '
        'yields no chapter', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildEpub3Book(
          manifestHref: _rawChapter,
          navItems: '<li><span>NGE-SEED Heading</span></li>'
              '<li><a href="$_rawChapter">NGE-SEED 第一章</a></li>',
        ),
      );

      final List<EpubChapterRef> chapters = await bookRef.getChapters();

      expect(
        chapters.map((EpubChapterRef chapter) => chapter.title),
        <String>['NGE-SEED 第一章'],
      );
    });

    // TC-CHR-2 [Error guessing]: a navPoint's content source names a file the
    // manifest never declared as (x)html, so it never entered
    // `bookRef.content.html`. Every reader up to this point is agnostic to
    // that mismatch — only `ChapterReader` cross-checks navigation against
    // content.
    test(
        'TC-CHR-2 [Error guessing]: a navPoint pointing at a file missing '
        'from content.html is rejected', () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(
            manifestItems: '$_ncxItem'
                '<item id="ch1" href="chapter1.xhtml" '
                'media-type="application/xhtml+xml"/>',
            spineItems: '<itemref idref="ch1"/>',
          ),
          'OEBPS/toc.ncx': _ncx(
            '<navPoint id="np-1" playOrder="1">'
            '<navLabel><text>NGE-SEED Ghost Chapter</text></navLabel>'
            '<content src="ghost.xhtml"/>'
            '</navPoint>',
          ),
          'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
        },
      );
      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);

      expect(
        bookRef.getChapters,
        _throwsMessageContaining('item with href = "ghost.xhtml" is missing'),
      );
    });

    // TC-CHR-3 [Equivalence partitioning]: the COMMON case — a chapter whose
    // file name does not carry the `_split_` marker — must skip the
    // split-siblings merge entirely, even when another html file's name
    // happens to contain this chapter's file name as a substring. Without
    // the guard, the sibling search (keyed on a `_split_`-free "part") would
    // match that unrelated file and wrongly pull it in.
    test(
        'TC-CHR-3 [Equivalence partitioning]: a non-split chapter never '
        'merges another file, even a name superset', () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(
            manifestItems: '$_ncxItem'
                '<item id="ch1" href="chapter1.xhtml" '
                'media-type="application/xhtml+xml"/>'
                '<item id="archived" href="archived_chapter1.xhtml" '
                'media-type="application/xhtml+xml"/>',
            spineItems: '<itemref idref="ch1"/>',
          ),
          'OEBPS/toc.ncx': _ncx(
            '<navPoint id="np-1" playOrder="1">'
            '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
            '<content src="chapter1.xhtml"/>'
            '</navPoint>',
          ),
          'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
          'OEBPS/archived_chapter1.xhtml': seedXhtml('NGE-SEED-ARCHIVED'),
        },
      );
      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);
      final EpubChapterRef chapter = (await bookRef.getChapters()).single;

      expect(chapter.otherContentFileNames, isEmpty);
      expect(chapter.otherTextContentFileRefs, isEmpty);
      expect(await chapter.readHtmlContent(), isNot(contains('ARCHIVED')));
    });

    // TC-CHR-4 [Regression]: the manifest and the NCX may each escape the
    // chapter's non-ASCII name or write it raw. All four combinations find
    // the chapter, keyed and named by the decoded name — including a manifest
    // that escapes what the NCX writes raw, the combination a lookup by
    // either side's own spelling misses.
    for (final List<String> row in <List<String>>[
      <String>[_escapedChapter, _rawChapter],
      <String>[_rawChapter, _escapedChapter],
      <String>[_escapedChapter, _escapedChapter],
      <String>[_rawChapter, _rawChapter],
    ]) {
      test(
          'TC-CHR-4 [Regression]: manifest "${row[0]}" and NCX "${row[1]}" '
          'find the chapter', () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildEpub2Book(manifestHref: row[0], ncxSrc: row[1]),
        );

        final EpubChapterRef chapter = (await bookRef.getChapters()).single;

        expect(bookRef.content.html.keys, <String>[_rawChapter]);
        expect(chapter.title, 'NGE-SEED 第一章');
        expect(chapter.contentFileName, _rawChapter);
        expect(chapter.epubTextContentFileRef.fileName, _rawChapter);
        expect(chapter.anchor, isNull);
        expect(await chapter.readHtmlContent(), contains('NGE-SEED-CJK-CH1'));
      });
    }

    // TC-CHR-5 [Regression]: the EPUB3 twin of TC-CHR-4 — a nav document
    // link meets the manifest's spelling however each side writes it.
    for (final List<String> row in <List<String>>[
      <String>[_escapedChapter, _rawChapter],
      <String>[_rawChapter, _escapedChapter],
    ]) {
      test(
          'TC-CHR-5 [Regression]: manifest "${row[0]}" and nav "${row[1]}" '
          'find the chapter', () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildEpub3Book(
            manifestHref: row[0],
            navItems: '<li><a href="${row[1]}">NGE-SEED 第一章</a></li>',
          ),
        );

        final EpubChapterRef chapter = (await bookRef.getChapters()).single;

        expect(chapter.title, 'NGE-SEED 第一章');
        expect(chapter.contentFileName, _rawChapter);
        expect(await chapter.readHtmlContent(), contains('NGE-SEED-CJK3-CH1'));
      });
    }

    // TC-CHR-6 [Equivalence partitioning]: the anchor is split off BEFORE the
    // name is decoded, so an escaped name followed by `#frag` resolves to the
    // decoded file with anchor `frag`; a bare `#` leaves an empty anchor,
    // not a null one. Subchapters resolve by the same rule, and a navPoint
    // with two labels takes the first as its title.
    test(
        'TC-CHR-6 [Equivalence partitioning]: an anchor on an escaped name '
        'resolves the decoded file and keeps the fragment', () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(
            manifestItems: '$_ncxItem'
                '<item id="ch1" href="$_escapedChapter" '
                'media-type="application/xhtml+xml"/>'
                '<item id="ch2" href="chapter2.xhtml" '
                'media-type="application/xhtml+xml"/>',
            spineItems: '<itemref idref="ch1"/><itemref idref="ch2"/>',
          ),
          'OEBPS/toc.ncx': _ncx(
            '<navPoint id="np-1" playOrder="1">'
            '<navLabel><text>NGE-SEED Label One</text></navLabel>'
            '<navLabel><text>NGE-SEED Label Two</text></navLabel>'
            '<content src="$_escapedChapter#frag"/>'
            '<navPoint id="np-1-1" playOrder="2">'
            '<navLabel><text>NGE-SEED Section</text></navLabel>'
            '<content src="chapter2.xhtml#"/>'
            '</navPoint>'
            '</navPoint>',
          ),
          'OEBPS/$_rawChapter': seedXhtml('NGE-SEED-CJK-CH1'),
          'OEBPS/chapter2.xhtml': seedXhtml('NGE-SEED-CH2'),
        },
      );
      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);

      final EpubChapterRef chapter = (await bookRef.getChapters()).single;

      expect(chapter.title, 'NGE-SEED Label One');
      expect(chapter.contentFileName, _rawChapter);
      expect(chapter.anchor, 'frag');
      expect(await chapter.readHtmlContent(), contains('NGE-SEED-CJK-CH1'));
      final EpubChapterRef section = chapter.subChapters.single;
      expect(section.title, 'NGE-SEED Section');
      expect(section.contentFileName, 'chapter2.xhtml');
      expect(section.anchor, '');
      expect(section.subChapters, isEmpty);
    });

    // TC-CHR-7 [Scenario/use-case]: a producer that cuts one document into
    // `_split_` files names only the first in the navigation. The chapter
    // collects every other file of the family — by decoded name, in manifest
    // order, not name order — skips an unrelated file, and reads them all as
    // one text in that order.
    test(
        'TC-CHR-7 [Scenario]: a split chapter collects its siblings in '
        'manifest order', () async {
      const List<String> manifestOrder = <String>[
        'part_split_000.xhtml',
        'part_split_002.xhtml',
        'other.xhtml',
        'part_split_%E4%B8%80.xhtml',
        'part_split_001.xhtml',
      ];
      final String htmlItems = <String>[
        for (int i = 0; i < manifestOrder.length; i++)
          '<item id="item$i" href="${manifestOrder[i]}" media-type="application/xhtml+xml"/>',
      ].join();
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(
            manifestItems: '$_ncxItem$htmlItems',
            spineItems: '<itemref idref="item0"/>',
          ),
          'OEBPS/toc.ncx': _ncx(
            '<navPoint id="np-1" playOrder="1">'
            '<navLabel><text>NGE-SEED Split Chapter</text></navLabel>'
            '<content src="part_split_000.xhtml"/>'
            '</navPoint>',
          ),
          'OEBPS/part_split_000.xhtml': seedXhtml('NGE-SEED-SPLIT-000'),
          'OEBPS/part_split_002.xhtml': seedXhtml('NGE-SEED-SPLIT-002'),
          'OEBPS/other.xhtml': seedXhtml('NGE-SEED-OTHER'),
          'OEBPS/part_split_一.xhtml': seedXhtml('NGE-SEED-SPLIT-ONE'),
          'OEBPS/part_split_001.xhtml': seedXhtml('NGE-SEED-SPLIT-001'),
        },
      );
      final EpubBookRef bookRef = await const EpubReader().openBook(bytes);

      final EpubChapterRef chapter = (await bookRef.getChapters()).single;

      const List<String> siblings = <String>[
        'part_split_002.xhtml',
        'part_split_一.xhtml',
        'part_split_001.xhtml',
      ];
      expect(chapter.contentFileName, 'part_split_000.xhtml');
      expect(chapter.otherContentFileNames, siblings);
      expect(
        chapter.otherTextContentFileRefs
            .map((EpubTextContentFileRef fileRef) => fileRef.fileName),
        siblings,
      );
      final String html = await chapter.readHtmlContent();
      expect(html, isNot(contains('NGE-SEED-OTHER')));
      final List<int> positions = <String>[
        'NGE-SEED-SPLIT-000',
        'NGE-SEED-SPLIT-002',
        'NGE-SEED-SPLIT-ONE',
        'NGE-SEED-SPLIT-001',
      ].map(html.indexOf).toList();
      expect(positions, everyElement(greaterThanOrEqualTo(0)));
      expect(positions, orderedEquals(<int>[...positions]..sort()));
    });

    // TC-CHR-8 [Error guessing]: a link to an undeclared file is reported by
    // its DECODED name — the name that was looked up, and the one a reader
    // of the error recognises.
    test(
        'TC-CHR-8 [Error guessing]: a missing escaped link is reported by its '
        'decoded name', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildEpub2Book(
          manifestHref: _rawChapter,
          ncxSrc: 'ghost%20page.xhtml#frag',
        ),
      );

      expect(
        bookRef.getChapters,
        throwsA(isA<EpubUnresolvedReferenceException>().having(
          (EpubUnresolvedReferenceException e) => e.message,
          'message',
          'Incorrect EPUB manifest: item with href = "ghost page.xhtml" is '
              'missing.',
        )),
      );
    });
  });
}
