// Regression coverage for `NavigationReader`'s EPUB3 nav-internal-link base
// path resolution (packages/epubx/lib/src/readers/navigation_reader.dart).
//
// Bug: the base directory used to resolve relative hrefs found inside an
// EPUB3 nav document (the manifest item with `properties="nav"`) used to be
// computed by combining the OPF's own directory with the nav item's href,
// then unconditionally dropping the first path segment
// (`..removeAt(0)`) — an assumption that the OPF always lives exactly one
// folder above the content (the classic `OEBPS/` layout). When the OPF
// instead sits at the ZIP root and content lives under a named subfolder,
// that assumption eats the real content folder from the base, so every
// nav-internal relative link resolves one folder too shallow.
// `ContentReader.parseContentMap` keys `Content.Html` by the RAW manifest
// href (not the resolved base), so the mis-resolved `ContentFileName` misses
// the lookup and `ChapterReader.getChaptersImpl` throws
// `Exception('Incorrect EPUB manifest: item with href = "..." is missing.')`
// for every navPoint — the whole TOC fails, not a single entry.
//
// Fixed shape: `navDirectory = ZipPathUtils.getDirectoryPath(tocManifestItem.Href!)`
// — the nav item's own href directory, independent of where the OPF sits.
//
// Fixtures are minimal synthetic EPUBs assembled in-memory with
// `package:archive`'s `ZipEncoder` (mirrors the existing fixture style in
// `epub_book_loader_pick_metadata_test.dart` / `epub_import_guard_test.dart`)
// — never the real ~45 MB repro book. The EPUB3 nav.xhtml shape (namespaces,
// the single-`<ol>` `<nav epub:type="toc">` structure) is cross-checked
// against the bundled `assets/samples/book.epub` fixture, which this parser
// is independently known to read correctly.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:test/test.dart';

/// OPF at the ZIP root, all content under a named subfolder (`sub/xhtml/`).
/// This is the layout that regressed: the nav item's href
/// (`sub/xhtml/nav.xhtml`) has two path segments before the file name, and
/// the old base resolution dropped the first one (`sub`) unconditionally.
Uint8List _buildRootOpfSubfolderContentEpub() {
  final Archive archive = Archive()
    ..addFile(
      ArchiveFile(
        'mimetype',
        'application/epub+zip'.length,
        'application/epub+zip'.codeUnits,
      )..compress = false,
    )
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles>'
            '<rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>'
            '</rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'content.opf',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:root-opf-subfolder</dc:identifier>'
            '<dc:title>Root OPF Subfolder Content</dc:title>'
            '<dc:language>en</dc:language>'
            '</metadata>'
            '<manifest>'
            '<item id="nav" href="sub/xhtml/nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="ch1" href="sub/xhtml/chapter1.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="ch2" href="sub/xhtml/chapter2.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine>'
            '<itemref idref="ch1"/>'
            '<itemref idref="ch2"/>'
            '</spine>'
            '</package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'sub/xhtml/nav.xhtml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<!DOCTYPE html>'
            '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
            '<head><title>Navigation</title></head>'
            '<body>'
            '<nav epub:type="toc">'
            '<ol>'
            '<li><a href="chapter1.xhtml">Chapter 1</a></li>'
            '<li><a href="chapter2.xhtml">Chapter 2</a></li>'
            '</ol>'
            '</nav>'
            '</body>'
            '</html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'sub/xhtml/chapter1.xhtml',
        '<html><body><p>Root layout chapter 1</p></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'sub/xhtml/chapter2.xhtml',
        '<html><body><p>Root layout chapter 2</p></body></html>',
      ),
    );

  final List<int>? encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('ZipEncoder.encode returned null');
  }
  return Uint8List.fromList(encoded);
}

/// Classic layout: the OPF and its nav document both live directly under
/// `OEBPS/`. Must keep resolving correctly — this is the same shape the
/// bundled `assets/samples/book.epub` fixture uses.
Uint8List _buildClassicOebpsEpub() {
  final Archive archive = Archive()
    ..addFile(
      ArchiveFile(
        'mimetype',
        'application/epub+zip'.length,
        'application/epub+zip'.codeUnits,
      )..compress = false,
    )
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles>'
            '<rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>'
            '</rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/package.opf',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:classic-oebps</dc:identifier>'
            '<dc:title>Classic OEBPS Layout</dc:title>'
            '<dc:language>en</dc:language>'
            '</metadata>'
            '<manifest>'
            '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="ch2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine>'
            '<itemref idref="ch1"/>'
            '<itemref idref="ch2"/>'
            '</spine>'
            '</package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/nav.xhtml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<!DOCTYPE html>'
            '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
            '<head><title>Navigation</title></head>'
            '<body>'
            '<nav epub:type="toc">'
            '<ol>'
            '<li><a href="chapter1.xhtml">Chapter 1</a></li>'
            '<li><a href="chapter2.xhtml">Chapter 2</a></li>'
            '</ol>'
            '</nav>'
            '</body>'
            '</html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/chapter1.xhtml',
        '<html><body><p>Classic layout chapter 1</p></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/chapter2.xhtml',
        '<html><body><p>Classic layout chapter 2</p></body></html>',
      ),
    );

  final List<int>? encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('ZipEncoder.encode returned null');
  }
  return Uint8List.fromList(encoded);
}

/// OPF nested one level (`OEBPS/package.opf`) with its nav document ANOTHER
/// level deeper (`OEBPS/xhtml/nav.xhtml`) than the OPF itself — a third,
/// distinct base-resolution shape: neither "OPF and nav share a directory"
/// (the classic layout) nor "OPF at the ZIP root" (the regressing layout).
Uint8List _buildNestedOpfDeeperNavEpub() {
  final Archive archive = Archive()
    ..addFile(
      ArchiveFile(
        'mimetype',
        'application/epub+zip'.length,
        'application/epub+zip'.codeUnits,
      )..compress = false,
    )
    ..addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles>'
            '<rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>'
            '</rootfiles>'
            '</container>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/package.opf',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:nested-opf-deeper-nav</dc:identifier>'
            '<dc:title>Nested OPF Deeper Nav</dc:title>'
            '<dc:language>en</dc:language>'
            '</metadata>'
            '<manifest>'
            '<item id="nav" href="xhtml/nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="ch1" href="xhtml/chapter1.xhtml" media-type="application/xhtml+xml"/>'
            '<item id="ch2" href="xhtml/chapter2.xhtml" media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine>'
            '<itemref idref="ch1"/>'
            '<itemref idref="ch2"/>'
            '</spine>'
            '</package>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/xhtml/nav.xhtml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<!DOCTYPE html>'
            '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
            '<head><title>Navigation</title></head>'
            '<body>'
            '<nav epub:type="toc">'
            '<ol>'
            '<li><a href="chapter1.xhtml">Chapter 1</a></li>'
            '<li><a href="chapter2.xhtml">Chapter 2</a></li>'
            '</ol>'
            '</nav>'
            '</body>'
            '</html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/xhtml/chapter1.xhtml',
        '<html><body><p>Nested layout chapter 1</p></body></html>',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'OEBPS/xhtml/chapter2.xhtml',
        '<html><body><p>Nested layout chapter 2</p></body></html>',
      ),
    );

  final List<int>? encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('ZipEncoder.encode returned null');
  }
  return Uint8List.fromList(encoded);
}

void main() {
  group('NavigationReader EPUB3 nav base-path resolution', () {
    // TC-NAV-1 [Scenario/use-case]: OPF at the ZIP root with content under a
    // named subfolder — the regressing layout. Both chapters resolve, and
    // their ContentFileName matches the raw manifest href exactly (proving
    // the 'sub' folder segment survived nav-internal link resolution rather
    // than being dropped as an assumed OPF-container folder).
    test(
      'TC-NAV-1 [Scenario]: OPF at root + subfolder content resolves every '
      'chapter with ContentFileName matching its manifest href',
      () async {
        final EpubBookRef bookRef = await EpubReader.openBook(
          _buildRootOpfSubfolderContentEpub(),
        );

        final List<EpubChapterRef> chapters = await bookRef.getChapters();

        expect(chapters, hasLength(2));
        expect(chapters[0].ContentFileName, 'sub/xhtml/chapter1.xhtml');
        expect(chapters[1].ContentFileName, 'sub/xhtml/chapter2.xhtml');
        expect(chapters[0].Title, 'Chapter 1');
        expect(chapters[1].Title, 'Chapter 2');
        expect(
          await chapters[0].readHtmlContent(),
          '<html><body><p>Root layout chapter 1</p></body></html>',
        );
        expect(
          await chapters[1].readHtmlContent(),
          '<html><body><p>Root layout chapter 2</p></body></html>',
        );
      },
    );

    // TC-NAV-2 [Scenario/use-case]: classic OEBPS/-package.opf +
    // OEBPS/nav.xhtml layout must keep resolving correctly — no regression
    // for the layout that accidentally masked this bug before the fix.
    test(
      'TC-NAV-2 [Scenario]: classic OEBPS layout still resolves every '
      'chapter with ContentFileName matching its manifest href',
      () async {
        final EpubBookRef bookRef = await EpubReader.openBook(
          _buildClassicOebpsEpub(),
        );

        final List<EpubChapterRef> chapters = await bookRef.getChapters();

        expect(chapters, hasLength(2));
        expect(chapters[0].ContentFileName, 'chapter1.xhtml');
        expect(chapters[1].ContentFileName, 'chapter2.xhtml');
        expect(
          await chapters[0].readHtmlContent(),
          '<html><body><p>Classic layout chapter 1</p></body></html>',
        );
      },
    );

    // TC-NAV-3 [Equivalence partitioning]: OPF nested one level with its nav
    // document another level deeper than the OPF — a third base-resolution
    // equivalence class distinct from both TC-NAV-1 (OPF at the root) and
    // TC-NAV-2 (nav alongside the OPF).
    test(
      'TC-NAV-3 [Equivalence partitioning]: nav one level deeper than a '
      'non-root OPF still resolves every chapter with ContentFileName '
      'matching its manifest href',
      () async {
        final EpubBookRef bookRef = await EpubReader.openBook(
          _buildNestedOpfDeeperNavEpub(),
        );

        final List<EpubChapterRef> chapters = await bookRef.getChapters();

        expect(chapters, hasLength(2));
        expect(chapters[0].ContentFileName, 'xhtml/chapter1.xhtml');
        expect(chapters[1].ContentFileName, 'xhtml/chapter2.xhtml');
        expect(
          await chapters[0].readHtmlContent(),
          '<html><body><p>Nested layout chapter 1</p></body></html>',
        );
      },
    );
  });
}
