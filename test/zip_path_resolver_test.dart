// `ZipPathResolver.combine` — the one place a path an EPUB names is turned
// into the name of a ZIP entry.
//
// The constraint this file pins: a file named in Chinese or Japanese must be
// found. ZIP entry names are raw UTF-8, so neither half of the lookup may
// percent-encode: `combine` must not (which rules out `Uri.normalizePath`),
// and decoding an href must not throw on a raw non-ASCII character (which
// rules out `Uri.decodeFull`, and most CJK books write their hrefs raw). The
// unit cases pin the resolver; the end-to-end cases pin that each reader that
// reaches it (content files, the EPUB2 NCX, the EPUB3 nav document) actually
// finds a non-ASCII entry.
//
// Techniques: boundary value (`..` above the root, empty directory, `.` and
// empty segments), regression (non-ASCII names), scenario (whole books whose
// files are named in CJK).
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/utils/zip_path_resolver.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

const ZipPathResolver _resolver = ZipPathResolver();

const String _opfHead = '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
    'unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="uid">urn:uuid:NGE-SEED-CJK</dc:identifier>'
    '<dc:title>NGE-SEED CJK Book</dc:title>'
    '<dc:language>zh-TW</dc:language>'
    '</metadata>';

String _ncx(String src) => '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-CJK"/></head>'
    '<docTitle><text>NGE-SEED CJK Book</text></docTitle>'
    '<navMap>'
    '<navPoint id="np-1" playOrder="1">'
    '<navLabel><text>NGE-SEED 第一章</text></navLabel>'
    '<content src="$src"/>'
    '</navPoint>'
    '</navMap>'
    '</ncx>';

/// An EPUB2 book whose OPF, NCX and chapter all carry CJK file names, the
/// chapter one directory down.
///
/// [ncxHref] and [chapterHref] are how the manifest spells those two files
/// (the chapter's spelling is also what the NCX links to); the archive
/// entries are always the raw names. The defaults write them raw, the shape
/// most books use.
Uint8List _buildEpub2CjkBook({
  String ncxHref = '目錄.ncx',
  String chapterHref = '文字/第一章.xhtml',
}) =>
    buildEpubArchive(
      opfPath: 'OEBPS/內容.opf',
      textEntries: <String, String>{
        'OEBPS/內容.opf': '$_opfHead'
            '<manifest>'
            '<item id="ncx" href="$ncxHref" '
            'media-type="application/x-dtbncx+xml"/>'
            '<item id="ch1" href="$chapterHref" '
            'media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine toc="ncx"><itemref idref="ch1"/></spine>'
            // An empty guide, so the writer (which cannot write a book
            // without one) can take this book too.
            '<guide/>'
            '</package>',
        'OEBPS/目錄.ncx': _ncx(chapterHref),
        'OEBPS/文字/第一章.xhtml': seedXhtml('NGE-SEED-CJK-CH1'),
      },
    );

/// An EPUB3 book whose nav document has a CJK name that the manifest
/// percent-encodes, as an `href` is a URL and may legitimately do. The
/// chapter's href is written raw, the other shape real books use.
Uint8List _buildEpub3EncodedNavBook() => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:NGE-SEED-CJK3</dc:identifier>'
            '<dc:title>NGE-SEED CJK Nav Book</dc:title>'
            '<dc:language>ja</dc:language>'
            '</metadata>'
            '<manifest>'
            '<item id="nav" properties="nav" '
            'href="%E7%9B%AE%E6%AC%A1.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<item id="ch1" href="第一章.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine><itemref idref="ch1"/></spine>'
            '</package>',
        'OEBPS/目次.xhtml': '<?xml version="1.0" encoding="UTF-8"?>'
            '<html xmlns="http://www.w3.org/1999/xhtml" '
            'xmlns:epub="http://www.idpf.org/2007/ops">'
            '<head><title>NGE-SEED 目次</title></head>'
            '<body><nav epub:type="toc"><ol>'
            '<li><a href="第一章.xhtml">NGE-SEED 第一章</a></li>'
            '</ol></nav></body>'
            '</html>',
        'OEBPS/第一章.xhtml': seedXhtml('NGE-SEED-CJK3-CH1'),
      },
    );

void main() {
  group('ZipPathResolver.combine', () {
    // TC-ZPR-1 [Regression]: a non-ASCII name comes back byte-for-byte as it
    // went in — no percent-encoding.
    test('TC-ZPR-1 [Regression]: non-ASCII names are not percent-encoded', () {
      expect(_resolver.combine('OEBPS', '第一章.xhtml'), 'OEBPS/第一章.xhtml');
      expect(_resolver.combine('本文', 'ページ.xhtml'), '本文/ページ.xhtml');
    });

    // TC-ZPR-2 [Boundary value]: `..` climbs one directory, and a `..` with
    // nothing left to climb is dropped rather than kept or thrown.
    test('TC-ZPR-2 [Boundary]: `..` resolves, and stops at the root', () {
      expect(_resolver.combine('OEBPS/文字', '../圖片/封面.png'), 'OEBPS/圖片/封面.png');
      expect(_resolver.combine('OEBPS', '../../根.xhtml'), '根.xhtml');
    });

    // TC-ZPR-3 [Boundary value]: `.` and empty segments are removed, so the
    // result is a canonical entry name.
    test('TC-ZPR-3 [Boundary]: `.` and empty segments are removed', () {
      expect(_resolver.combine('OEBPS/', './第一章.xhtml'), 'OEBPS/第一章.xhtml');
    });

    // TC-ZPR-4 [Boundary value]: with no directory, the name is the entry —
    // the OPF sits at the container root.
    test('TC-ZPR-4 [Boundary]: a null or empty directory yields the name', () {
      expect(_resolver.combine(null, '第一章.xhtml'), '第一章.xhtml');
      expect(_resolver.combine('', 'a/../第一章.xhtml'), '第一章.xhtml');
    });

    // TC-ZPR-5 [Equivalence]: an ASCII name with a space is kept literal —
    // the archive entry is `ch one.xhtml`, not `ch%20one.xhtml`; callers
    // decode before they combine.
    test('TC-ZPR-5 [Equivalence]: a space is kept literal', () {
      expect(_resolver.combine('OEBPS', 'ch one.xhtml'), 'OEBPS/ch one.xhtml');
    });

    // TC-ZPR-13 [Equivalence]: a `\` separator, as books built on Windows
    // write it, resolves like a `/` — including through `..`.
    test('TC-ZPR-13 [Equivalence]: a backslash separates like a slash', () {
      expect(_resolver.combine('OEBPS', r'文字\第一章.xhtml'), 'OEBPS/文字/第一章.xhtml');
      expect(_resolver.combine(r'OEBPS\文字', r'..\封面.png'), 'OEBPS/封面.png');
    });
  });

  group('ZipPathResolver.decodeHref', () {
    // TC-ZPR-9 [Regression]: a raw non-ASCII href — the shape most CJK books
    // write — comes back unchanged instead of throwing.
    test('TC-ZPR-9 [Regression]: a raw non-ASCII href is kept as written', () {
      expect(_resolver.decodeHref('文字/第一章.xhtml'), '文字/第一章.xhtml');
    });

    // TC-ZPR-10 [Equivalence]: escapes decode, including a multi-byte UTF-8
    // character spelled across three escapes and lower-case hex.
    test('TC-ZPR-10 [Equivalence]: escapes decode, multi-byte and lower-case',
        () {
      expect(_resolver.decodeHref('ch%20one.xhtml'), 'ch one.xhtml');
      expect(_resolver.decodeHref('%E7%AC%AC%e4%b8%80%E7%AB%A0.xhtml'),
          '第一章.xhtml');
    });

    // TC-ZPR-11 [Boundary value]: a `%` that does not start an escape — not
    // followed by two hex digits, or cut off by the end — is kept literally
    // instead of throwing.
    test('TC-ZPR-11 [Boundary]: a `%` that is not an escape is kept', () {
      expect(_resolver.decodeHref('100%.xhtml'), '100%.xhtml');
      expect(_resolver.decodeHref('a%zz.xhtml'), 'a%zz.xhtml');
      expect(_resolver.decodeHref('end%4'), 'end%4');
      expect(_resolver.decodeHref('end%'), 'end%');
    });

    // TC-ZPR-12 [Equivalence]: raw non-ASCII and escapes in one href.
    test('TC-ZPR-12 [Equivalence]: raw and escaped characters mix', () {
      expect(_resolver.decodeHref('第%E4%B8%80章%20a.xhtml'), '第一章 a.xhtml');
    });

    // TC-ZPR-14 [Error guessing]: escapes that decode to bytes which are not
    // UTF-8 — a lone `%FF`, or a three-byte character cut after two — leave
    // the href exactly as written. Decoding leniently instead would turn
    // `%FF.xhtml` and `%FE.xhtml` into the same `�.xhtml`.
    test('TC-ZPR-14 [Error guessing]: escapes that are not UTF-8 are kept', () {
      expect(_resolver.decodeHref('%FF.xhtml'), '%FF.xhtml');
      expect(_resolver.decodeHref('%E7%AC.xhtml'), '%E7%AC.xhtml');
    });

    // TC-ZPR-15 [Boundary value]: the characters just outside each hex digit
    // range — `/` and `:` around `0-9`, `@` and `G` around `A-F`, `` ` `` and
    // `g` around `a-f` — do not start an escape, while the range ends do.
    test('TC-ZPR-15 [Boundary]: only 0-9, A-F and a-f are hex digits', () {
      for (final String notHex in <String>['/', ':', '@', 'G', '`', 'g']) {
        expect(_resolver.decodeHref('a%${notHex}0'), 'a%${notHex}0',
            reason: '`$notHex` is not a hex digit');
        expect(_resolver.decodeHref('a%0$notHex'), 'a%0$notHex',
            reason: '`$notHex` is not a hex digit');
      }
      // `0`, `9`, `A`, `F`, `a` and `f` each as a hex digit of an escape:
      // `%30` `%39` → `0` `9`, `%2A` `%2F` → `*` `/`, `%2a` `%2f` → `*` `/`.
      expect(_resolver.decodeHref('%30%39%2A%2F%2a%2f'), '09*/*/');
    });
  });

  group('non-ASCII file names, end to end', () {
    // TC-ZPR-6 [Scenario]: an EPUB2 book with CJK names for the OPF, the NCX
    // and a chapter one directory down opens, builds its chapter tree, and
    // reads the chapter's text — the content-file path through `combine`.
    test('TC-ZPR-6 [Scenario]: an EPUB2 book named in CJK reads its chapter',
        () async {
      final EpubBook book =
          await const EpubReader().readBook(_buildEpub2CjkBook());

      expect(book.chapters!.single.title, 'NGE-SEED 第一章');
      expect(book.chapters!.single.htmlContent, contains('NGE-SEED-CJK-CH1'));
    });

    // TC-ZPR-7 [Scenario]: the lazy path — `openBook` then read one content
    // file through its ref, the path NovelGlide's reader takes.
    test('TC-ZPR-7 [Scenario]: a content ref with a CJK name reads its entry',
        () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildEpub2CjkBook());

      final String html =
          await bookRef.content!.html!['文字/第一章.xhtml']!.readContentAsText();

      expect(html, contains('NGE-SEED-CJK-CH1'));
    });

    // TC-ZPR-8 [Regression]: an EPUB3 nav document whose manifest href is
    // percent-encoded is decoded before it is looked up.
    test(
        'TC-ZPR-8 [Regression]: a percent-encoded EPUB3 nav href resolves to '
        'its CJK entry', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildEpub3EncodedNavBook());

      final List<EpubChapterRef> chapters = await bookRef.getChapters();

      expect(chapters.single.title, 'NGE-SEED 第一章');
      expect(await chapters.single.readHtmlContent(),
          contains('NGE-SEED-CJK3-CH1'));
    });

    // TC-ZPR-16 [Regression]: the EPUB2 twin of TC-ZPR-8 — an NCX whose
    // manifest href is percent-encoded is decoded before it is looked up.
    test(
        'TC-ZPR-16 [Regression]: a percent-encoded NCX href resolves to its '
        'CJK entry', () async {
      final EpubBook book = await const EpubReader()
          .readBook(_buildEpub2CjkBook(ncxHref: '%E7%9B%AE%E9%8C%84.ncx'));

      expect(book.chapters!.single.title, 'NGE-SEED 第一章');
    });

    // TC-ZPR-17 [Scenario]: a book that percent-encodes the chapter href in
    // both the manifest and the NCX. The content maps are keyed by the
    // manifest's spelling, so the chapter is found under the NCX's own
    // spelling rather than only its decoded form.
    test(
        'TC-ZPR-17 [Scenario]: a chapter href escaped the same way in the '
        'manifest and the NCX is found', () async {
      final EpubBook book = await const EpubReader().readBook(
          _buildEpub2CjkBook(
              chapterHref:
                  '%E6%96%87%E5%AD%97/%E7%AC%AC%E4%B8%80%E7%AB%A0.xhtml'));

      expect(book.chapters!.single.htmlContent, contains('NGE-SEED-CJK-CH1'));
    });

    // TC-ZPR-18 [Scenario]: writing a book back out names each archive entry
    // by its file name, not by the manifest's escaped href — otherwise the
    // written book could not find its own chapter when read back.
    test('TC-ZPR-18 [Scenario]: the writer names entries by decoded file name',
        () async {
      final EpubBook book = await const EpubReader().readBook(
          _buildEpub2CjkBook(
              chapterHref:
                  '%E6%96%87%E5%AD%97/%E7%AC%AC%E4%B8%80%E7%AB%A0.xhtml'));

      final List<String> entries = ZipDecoder()
          .decodeBytes(const EpubWriter().writeBook(book)!)
          .files
          .map((ArchiveFile file) => file.name)
          .toList();

      expect(entries, contains('OEBPS/文字/第一章.xhtml'));
      expect(
          entries,
          isNot(contains(
              'OEBPS/%E6%96%87%E5%AD%97/%E7%AC%AC%E4%B8%80%E7%AB%A0.xhtml')));
    });
  });
}
