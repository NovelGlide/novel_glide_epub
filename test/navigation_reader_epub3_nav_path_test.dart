// Where an EPUB3 nav document (the manifest item with `properties="nav"`)
// sits in the archive, and how `NavigationReader` resolves the relative
// hrefs inside it.
//
// A nav-internal href is relative to the nav document, and the chapter it
// names is looked up in `content.html`, which is keyed by manifest href —
// relative to the OPF. So the reader prefixes each nav href with the nav
// item's own manifest-href directory, whatever directory the OPF sits in.
// A base that assumed the OPF lives one folder above the content (the
// classic `OEBPS/` layout) would drop a real content folder when the OPF
// sits at the ZIP root, and every entry of the table of contents would then
// name a file the manifest does not have. The three layouts below are the
// three ways the OPF and the nav document can sit relative to each other.
//
// Fixtures are minimal synthetic EPUBs assembled in memory with
// `package:archive`'s `ZipEncoder`; the nav.xhtml shape (namespaces, the
// single-`<ol>` `<nav epub:type="toc">` structure) is the one real EPUB3
// books use.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

/// OPF at the ZIP root, all content under a named subfolder (`sub/xhtml/`).
/// The nav item's href (`sub/xhtml/nav.xhtml`) has two path segments before
/// the file name, and a base that assumed an OPF folder would drop the first
/// one (`sub`).
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
/// `OEBPS/`, so the nav base is empty.
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

/// Nav-point sources of [bookRef], in table-of-contents order.
List<String?> _navSources(EpubBookRef bookRef) =>
    bookRef.schema.navigation.navMap.points
        .map((EpubNavigationPoint point) => point.content.source)
        .toList();

void main() {
  group('NavigationReader EPUB3 nav base-path resolution', () {
    // TC-NAV-1 [Scenario/use-case]: OPF at the ZIP root with content under a
    // named subfolder. Each nav href is prefixed with the nav item's own
    // directory, so both chapters resolve and their contentFileName matches
    // the manifest href exactly — the 'sub' folder segment is kept rather
    // than dropped as an assumed OPF-container folder.
    test(
      'TC-NAV-1 [Scenario]: OPF at root + subfolder content resolves every '
      'chapter with contentFileName matching its manifest href',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildRootOpfSubfolderContentEpub(),
        );

        expect(_navSources(bookRef), <String>[
          'sub/xhtml/chapter1.xhtml',
          'sub/xhtml/chapter2.xhtml',
        ]);

        final List<EpubChapterRef> chapters = await bookRef.getChapters();

        expect(chapters, hasLength(2));
        expect(chapters[0].contentFileName, 'sub/xhtml/chapter1.xhtml');
        expect(chapters[1].contentFileName, 'sub/xhtml/chapter2.xhtml');
        expect(chapters[0].title, 'Chapter 1');
        expect(chapters[1].title, 'Chapter 2');
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

    // TC-NAV-2 [Scenario/use-case]: classic OEBPS/package.opf +
    // OEBPS/nav.xhtml layout — the nav base is empty, so the hrefs are kept
    // exactly as the nav document writes them.
    test(
      'TC-NAV-2 [Scenario]: classic OEBPS layout still resolves every '
      'chapter with contentFileName matching its manifest href',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildClassicOebpsEpub(),
        );

        expect(
          _navSources(bookRef),
          <String>['chapter1.xhtml', 'chapter2.xhtml'],
        );

        final List<EpubChapterRef> chapters = await bookRef.getChapters();

        expect(chapters, hasLength(2));
        expect(chapters[0].contentFileName, 'chapter1.xhtml');
        expect(chapters[1].contentFileName, 'chapter2.xhtml');
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
      'non-root OPF still resolves every chapter with contentFileName '
      'matching its manifest href',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildNestedOpfDeeperNavEpub(),
        );

        expect(_navSources(bookRef), <String>[
          'xhtml/chapter1.xhtml',
          'xhtml/chapter2.xhtml',
        ]);

        final List<EpubChapterRef> chapters = await bookRef.getChapters();

        expect(chapters, hasLength(2));
        expect(chapters[0].contentFileName, 'xhtml/chapter1.xhtml');
        expect(chapters[1].contentFileName, 'xhtml/chapter2.xhtml');
        expect(
          await chapters[0].readHtmlContent(),
          '<html><body><p>Nested layout chapter 1</p></body></html>',
        );
      },
    );

    // TC-NAV-4 [Equivalence partitioning]: the nav item's manifest href is a
    // URL, so it may escape its file name; the archive entry is found under
    // the decoded name.
    test(
      'TC-NAV-4 [Equivalence partitioning]: a percent-encoded nav href finds '
      'the nav document under its decoded name',
      () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          buildEpubArchive(
            opfPath: 'OEBPS/package.opf',
            textEntries: <String, String>{
              'OEBPS/package.opf': '<?xml version="1.0" encoding="UTF-8"?>'
                  '<package xmlns="http://www.idpf.org/2007/opf" '
                  'version="3.0" unique-identifier="uid">'
                  '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
                  '<dc:identifier id="uid">urn:uuid:NGE-SEED-NAV-ESCAPED'
                  '</dc:identifier>'
                  '<dc:title>NGE-SEED Escaped Nav</dc:title>'
                  '</metadata>'
                  '<manifest>'
                  '<item id="nav" href="NGE-SEED%20n%C3%A4v.xhtml" '
                  'media-type="application/xhtml+xml" properties="nav"/>'
                  '<item id="ch1" href="chapter1.xhtml" '
                  'media-type="application/xhtml+xml"/>'
                  '</manifest>'
                  '<spine><itemref idref="ch1"/></spine>'
                  '</package>',
              'OEBPS/NGE-SEED näv.xhtml':
                  '<?xml version="1.0" encoding="UTF-8"?>'
                      '<html xmlns="http://www.w3.org/1999/xhtml">'
                      '<head><title>NGE-SEED Navigation</title></head>'
                      '<body><nav><ol>'
                      '<li><a href="chapter1.xhtml">NGE-SEED Chapter One</a>'
                      '</li>'
                      '</ol></nav></body>'
                      '</html>',
              'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
            },
          ),
        );

        expect(_navSources(bookRef), <String>['chapter1.xhtml']);
      },
    );
  });
}
