// `ChapterReader` — turns the navigation map into the chapter-ref tree.
//
// The happy paths (single-file chapters, split-file chapters, anchors,
// subchapters) are exercised through `EpubBookRef.getChapters()` in
// `ref_entities_test.dart`, which is what a real caller uses. This file
// covers the guards `ChapterReader` itself carries: the two that a
// `bookRef.getChapters()` call cannot trip without an earlier reader already
// refusing the book, plus the split-siblings guard's common (non-split) case.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/readers/chapter_reader.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

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

Matcher _throwsMessageContaining(String fragment) => throwsA(
      isA<Exception>().having(
        (Exception e) => e.toString(),
        'message',
        contains(fragment),
      ),
    );

void main() {
  group('ChapterReader.getChapters', () {
    // TC-CHR-1 [Boundary value]: `getChapters` defends against a Navigation
    // that is null — unreachable through `EpubReader.openBook`, since
    // `SchemaReader`/`NavigationReader` always produce a non-null
    // `EpubNavigation` for either EPUB version, but a caller can hand
    // `ChapterReader` a hand-built `EpubBookRef` directly (as this test
    // does), and the guard is what keeps that call from a null check
    // failure on `NavMap!`.
    test(
        'TC-CHR-1 [Boundary]: a Schema with no Navigation yields no '
        'chapters', () {
      final EpubBookRef bookRef = EpubBookRef(Archive())
        ..Schema = EpubSchema();

      expect(const ChapterReader().getChapters(bookRef), isEmpty);
    });

    // TC-CHR-2 [Error guessing]: a navPoint's content source names a file the
    // manifest never declared as (x)html, so it never entered
    // `bookRef.Content!.Html!`. Every reader up to this point is agnostic to
    // that mismatch — only `ChapterReader` cross-checks navigation against
    // content.
    test(
        'TC-CHR-2 [Error guessing]: a navPoint pointing at a file missing '
        'from Content.Html is rejected', () async {
      final Uint8List bytes = buildEpubArchive(
        opfPath: 'OEBPS/content.opf',
        textEntries: <String, String>{
          'OEBPS/content.opf': _opf(
            manifestItems: '<item id="ncx" href="toc.ncx" '
                'media-type="application/x-dtbncx+xml"/>'
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
      final EpubBookRef bookRef = await EpubReader.openBook(bytes);

      expect(
        bookRef.getChapters,
        _throwsMessageContaining('item with href = "ghost.xhtml" is missing'),
      );
    });

    // TC-CHR-3 [Equivalence partitioning]: the COMMON case — a chapter whose
    // file name does not carry the `_split_` marker — must skip the
    // split-siblings merge entirely, even when another Html file's name
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
            manifestItems: '<item id="ncx" href="toc.ncx" '
                'media-type="application/x-dtbncx+xml"/>'
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
      final EpubBookRef bookRef = await EpubReader.openBook(bytes);
      final EpubChapterRef chapter = (await bookRef.getChapters()).single;

      expect(chapter.OtherContentFileNames, isEmpty);
      expect(chapter.otherTextContentFileRefs, isEmpty);
    });
  });
}
