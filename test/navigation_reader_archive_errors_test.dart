// `NavigationReader.readNavigation` refuses malformed books — one test per
// guard, on both the EPUB2 (NCX) and EPUB3 (nav document) branches.
//
// This parser is a trust boundary: the bytes come from a file the user picked,
// so every guard here is reached by real, merely-broken EPUBs, not only by
// hostile ones. Each fixture is built from a valid book minus exactly one
// piece, so a passing test attributes the failure to that piece alone.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

String _opfEpub2({
  String spine = '<spine toc="ncx"><itemref idref="ch1"/></spine>',
  String manifestExtra =
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
    'unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="uid">urn:uuid:NGE-SEED-NAV-ERRORS</dc:identifier>'
    '<dc:title>NGE-SEED Navigation Errors</dc:title>'
    '</metadata>'
    '<manifest>'
    '$manifestExtra'
    '<item id="ch1" href="chapter1.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '</manifest>'
    '$spine'
    '</package>';

String _opfEpub3({
  String navItem = '<item id="nav" href="nav.xhtml" '
      'media-type="application/xhtml+xml" properties="nav"/>',
}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
    'unique-identifier="uid">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="uid">urn:uuid:NGE-SEED-NAV3-ERRORS</dc:identifier>'
    '<dc:title>NGE-SEED Navigation3 Errors</dc:title>'
    '</metadata>'
    '<manifest>'
    '$navItem'
    '<item id="ch1" href="chapter1.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '</manifest>'
    '<spine><itemref idref="ch1"/></spine>'
    '</package>';

/// EPUB2 book whose NCX body is [ncx]; omit [ncx] to leave the declared NCX
/// entry out of the archive entirely.
Uint8List _epub2With({
  String? ncx,
  String? opf,
}) =>
    buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': opf ?? _opfEpub2(),
        if (ncx != null) 'OEBPS/toc.ncx': ncx,
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
      },
    );

Uint8List _epub3With({String? nav, String? opf}) => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': opf ?? _opfEpub3(),
        if (nav != null) 'OEBPS/nav.xhtml': nav,
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
      },
    );

/// A valid NCX with [omit] removed, so each test differs from a working book
/// by exactly one element.
String _ncxWithout(String omit) {
  const Map<String, String> parts = <String, String>{
    'head': '<head>'
        '<meta name="dtb:uid" content="urn:uuid:NGE-SEED-NAV-ERRORS"/>'
        '</head>',
    'docTitle': '<docTitle><text>NGE-SEED Title</text></docTitle>',
    'navMap': '<navMap>'
        '<navPoint id="np-1" playOrder="1">'
        '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
        '<content src="chapter1.xhtml"/>'
        '</navPoint>'
        '</navMap>',
  };
  final StringBuffer buffer = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">',
  );
  parts.forEach((String name, String xml) {
    if (name != omit) {
      buffer.write(xml);
    }
  });
  buffer.write('</ncx>');
  return buffer.toString();
}

Matcher _throwsMessageContaining(String fragment) => throwsA(
      isA<Exception>().having(
        (Exception e) => e.toString(),
        'message',
        contains(fragment),
      ),
    );

void main() {
  group('NavigationReader EPUB2 archive guards', () {
    // TC-NAVE-1 [Error guessing]: an EPUB2 spine with no `toc` attribute has
    // no NCX to point at.
    test(
      'TC-NAVE-1 [Error guessing]: EPUB2 spine without a toc attribute is '
      'rejected as an empty TOC ID',
      () {
        expect(
          () => EpubReader.openBook(
            _epub2With(
              ncx: _ncxWithout(''),
              opf: _opfEpub2(spine: '<spine><itemref idref="ch1"/></spine>'),
            ),
          ),
          _throwsMessageContaining('TOC ID is empty'),
        );
      },
    );

    // TC-NAVE-2 [Error guessing]: the spine's toc id names a manifest item
    // that does not exist.
    test(
      'TC-NAVE-2 [Error guessing]: EPUB2 toc id absent from the manifest is '
      'rejected',
      () {
        expect(
          () => EpubReader.openBook(
            _epub2With(
              ncx: _ncxWithout(''),
              opf: _opfEpub2(
                spine: '<spine toc="nge-seed-absent-ncx">'
                    '<itemref idref="ch1"/></spine>',
              ),
            ),
          ),
          _throwsMessageContaining(
            'TOC item nge-seed-absent-ncx not found in EPUB manifest',
          ),
        );
      },
    );

    // TC-NAVE-3 [Error guessing]: the manifest declares an NCX that the ZIP
    // does not carry.
    test(
      'TC-NAVE-3 [Error guessing]: EPUB2 NCX declared but missing from the '
      'archive is rejected',
      () {
        expect(
          () => EpubReader.openBook(_epub2With()),
          _throwsMessageContaining('not found in archive'),
        );
      },
    );

    // TC-NAVE-4 [Error guessing]: the NCX file parses as XML but has no `ncx`
    // root in the DAISY namespace.
    test(
      'TC-NAVE-4 [Error guessing]: TOC file without an ncx element is '
      'rejected',
      () {
        expect(
          () => EpubReader.openBook(
            _epub2With(ncx: '<?xml version="1.0"?><notNcx/>'),
          ),
          _throwsMessageContaining('does not contain ncx element'),
        );
      },
    );

    // TC-NAVE-5 [Equivalence partitioning]: each required NCX child — head,
    // docTitle, navMap — has its own guard; one case per element keeps the
    // failure attributable.
    for (final MapEntry<String, String> missing in <String, String>{
      'head': 'does not contain head element',
      'docTitle': 'does not contain docTitle element',
      'navMap': 'does not contain navMap element',
    }.entries) {
      test(
        'TC-NAVE-5 [Equivalence partitioning]: NCX without ${missing.key} is '
        'rejected',
        () {
          expect(
            () =>
                EpubReader.openBook(_epub2With(ncx: _ncxWithout(missing.key))),
            _throwsMessageContaining(missing.value),
          );
        },
      );
    }
  });

  group('NavigationReader EPUB3 archive guards', () {
    // TC-NAVE-6 [Error guessing]: no manifest item carries
    // `properties="nav"`, so an EPUB3 book has no table of contents at all.
    test(
      'TC-NAVE-6 [Error guessing]: EPUB3 manifest without a properties="nav" '
      'item is rejected',
      () {
        expect(
          () => EpubReader.openBook(
            _epub3With(
              nav: '<html><head/><body><nav><ol/></nav></body></html>',
              opf: _opfEpub3(
                navItem: '<item id="nav" href="nav.xhtml" '
                    'media-type="application/xhtml+xml"/>',
              ),
            ),
          ),
          _throwsMessageContaining('TOC item, not found in EPUB manifest'),
        );
      },
    );

    // TC-NAVE-7 [Error guessing]: the nav document is declared but absent
    // from the ZIP.
    test(
      'TC-NAVE-7 [Error guessing]: EPUB3 nav document declared but missing '
      'from the archive is rejected',
      () {
        expect(
          () => EpubReader.openBook(_epub3With()),
          _throwsMessageContaining('not found in archive'),
        );
      },
    );

    // TC-NAVE-8 [Error guessing]: an EPUB3 nav document with no `head`.
    test(
      'TC-NAVE-8 [Error guessing]: EPUB3 nav document without a head element '
      'is rejected',
      () {
        expect(
          () => EpubReader.openBook(
            _epub3With(nav: '<html><body><nav><ol/></nav></body></html>'),
          ),
          _throwsMessageContaining('does not contain head element'),
        );
      },
    );

    // TC-NAVE-9 [Error guessing]: an EPUB3 nav document with a head but no
    // `nav` element. The guard used to reuse the head-element wording; it now
    // names the element it actually looked for.
    test(
      'TC-NAVE-9 [Error guessing]: EPUB3 nav document without a nav element '
      'is rejected',
      () {
        expect(
          () => EpubReader.openBook(
            _epub3With(nav: '<html><head/><body><p>NGE-SEED</p></body></html>'),
          ),
          _throwsMessageContaining('does not contain nav element'),
        );
      },
    );
  });
}
