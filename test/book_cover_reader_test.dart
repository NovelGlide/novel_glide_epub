// `BookCoverReader` — both cover paths.
//
// `readBookCover` decodes and THROWS on a malformed cover; `readBookCoverBytes`
// returns raw bytes and never throws, so a book with a broken cover still
// opens. That difference is the point of the class, so every case below is
// stated for whichever of the two it belongs to.
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

const String _ncx = '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="urn:uuid:NGE-SEED-COVER"/></head>'
    '<docTitle><text>NGE-SEED Cover Book</text></docTitle>'
    '<navMap>'
    '<navPoint id="np-1" playOrder="1">'
    '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
    '<content src="chapter1.xhtml"/>'
    '</navPoint>'
    '</navMap>'
    '</ncx>';

/// An EPUB2 book with a configurable cover declaration.
///
/// [metaItems] is injected into `<metadata>`, [coverItems] into `<manifest>`;
/// set [includeImageEntry] to false to declare a cover whose archive entry is
/// absent.
Uint8List _buildCoverBook({
  String metaItems = '',
  String coverItems = '',
  bool includeImageEntry = true,
}) =>
    buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:NGE-SEED-COVER</dc:identifier>'
            '<dc:title>NGE-SEED Cover Book</dc:title>'
            '$metaItems'
            '</metadata>'
            '<manifest>'
            '<item id="ncx" href="toc.ncx" '
            'media-type="application/x-dtbncx+xml"/>'
            '<item id="ch1" href="chapter1.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '$coverItems'
            '</manifest>'
            '<spine toc="ncx"><itemref idref="ch1"/></spine>'
            '</package>',
        'OEBPS/toc.ncx': _ncx,
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-CH1'),
      },
      binaryEntries: <String, List<int>>{
        if (includeImageEntry) 'OEBPS/cover.png': seedPngBytes(),
      },
    );

const String _coverImageItem = '<item id="cover-img" href="cover.png" '
    'media-type="image/png"/>';
const String _coverMeta = '<meta name="cover" content="cover-img"/>';

Matcher _throwsMessageContaining(String fragment) => throwsA(
      isA<Exception>().having(
        (Exception e) => e.toString(),
        'message',
        contains(fragment),
      ),
    );

void main() {
  group('BookCoverReader.readBookCover (decoding, throwing)', () {
    // TC-COV-1 [Scenario/use-case]: the EPUB2 `<meta name="cover">` path
    // decodes to a real image.
    test('TC-COV-1 [Scenario]: a declared cover decodes to an image', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(metaItems: _coverMeta, coverItems: _coverImageItem),
      );

      final Image? cover = await bookRef.readCover();

      expect(cover, isNotNull);
      expect(cover!.width, 2);
      expect(cover.height, 2);
    });

    // TC-COV-2 [Equivalence partitioning]: no meta items at all, and meta
    // items with no `cover` entry, both mean "no cover" rather than an error.
    test(
        'TC-COV-2 [Equivalence partitioning]: a book with no meta items has '
        'no cover', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildCoverBook());

      expect(await bookRef.readCover(), isNull);
    });

    test(
        'TC-COV-3 [Equivalence partitioning]: meta items without a cover '
        'entry mean no cover', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: '<meta name="calibre:series" content="NGE-SEED"/>',
        ),
      );

      expect(await bookRef.readCover(), isNull);
    });

    // TC-COV-4 [Boundary value]: a cover meta with empty content is a
    // declared-but-unusable cover, which this path refuses loudly.
    test('TC-COV-4 [Boundary]: a cover meta with empty content is rejected',
        () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(metaItems: '<meta name="cover" content=""/>'),
      );

      expect(
        bookRef.readCover,
        _throwsMessageContaining('cover item content is missing'),
      );
    });

    // TC-COV-5 [Error guessing]: the cover meta names a manifest id that does
    // not exist.
    test(
        'TC-COV-5 [Error guessing]: a cover id absent from the manifest is '
        'rejected', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: '<meta name="cover" content="nge-seed-absent"/>',
        ),
      );

      expect(
        bookRef.readCover,
        _throwsMessageContaining('item with ID = "nge-seed-absent" is missing'),
      );
    });

    // TC-COV-6 [Error guessing]: the cover manifest item exists but is not an
    // image, so it never entered the images map.
    test(
        'TC-COV-6 [Error guessing]: a cover item that is not an image is '
        'rejected', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: '<meta name="cover" content="cover-page"/>',
          coverItems: '<item id="cover-page" href="cover.xhtml" '
              'media-type="application/xhtml+xml"/>',
        ),
      );

      expect(
        bookRef.readCover,
        _throwsMessageContaining('item with href = "cover.xhtml" is missing'),
      );
    });
  });

  group('BookCoverReader.readBookCoverBytes (raw, non-throwing)', () {
    // TC-COV-7 [Scenario/use-case]: the EPUB2 metadata path returns the raw
    // archive bytes, undecoded.
    test('TC-COV-7 [Scenario]: the EPUB2 meta path returns the raw PNG bytes',
        () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(metaItems: _coverMeta, coverItems: _coverImageItem),
      );

      expect(await bookRef.readCoverBytes(), seedPngBytes());
    });

    // TC-COV-8 [Equivalence partitioning]: the EPUB3 conventions — the
    // `cover-image` property, and the conventional `cover` / `cover-image`
    // ids — each resolve without any `<meta name="cover">`.
    for (final List<String> row in <List<String>>[
      <String>[
        'properties="cover-image"',
        '<item id="img-1" href="cover.png" media-type="image/png" properties="cover-image"/>',
      ],
      <String>[
        'properties="cover"',
        '<item id="img-1" href="cover.png" media-type="image/png" properties="cover"/>',
      ],
      <String>[
        'id="cover"',
        '<item id="cover" href="cover.png" media-type="image/png"/>',
      ],
      <String>[
        'id="cover-image"',
        '<item id="cover-image" href="cover.png" media-type="image/png"/>',
      ],
    ]) {
      test(
        'TC-COV-8 [Equivalence partitioning]: the manifest convention '
        '${row[0]} resolves the cover without a cover meta',
        () async {
          final EpubBookRef bookRef = await const EpubReader()
              .openBook(_buildCoverBook(coverItems: row[1]));

          expect(await bookRef.readCoverBytes(), seedPngBytes());
        },
      );
    }

    // TC-COV-9 [Equivalence partitioning]: a book declaring no cover by
    // either convention yields null, not an exception.
    test(
        'TC-COV-9 [Equivalence partitioning]: a book with no cover at all '
        'yields null bytes', () async {
      final EpubBookRef bookRef =
          await const EpubReader().openBook(_buildCoverBook());

      expect(await bookRef.readCoverBytes(), isNull);
    });

    // TC-COV-10 [Boundary value]: the same empty-content meta that
    // readBookCover rejects is silently treated as "no cover" here.
    test(
        'TC-COV-10 [Boundary]: an empty cover meta yields null bytes instead '
        'of throwing', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(metaItems: '<meta name="cover" content=""/>'),
      );

      expect(await bookRef.readCoverBytes(), isNull);
    });

    // TC-COV-11 [Error guessing]: an unresolvable cover id also degrades to
    // null rather than failing the open.
    test(
        'TC-COV-11 [Error guessing]: a cover id absent from the manifest '
        'yields null bytes', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: '<meta name="cover" content="nge-seed-absent"/>',
        ),
      );

      expect(await bookRef.readCoverBytes(), isNull);
    });

    // TC-COV-12 [Error guessing]: a cover item that is not an image is not in
    // the images map, so the href lookup misses.
    test(
        'TC-COV-12 [Error guessing]: a non-image cover item yields null '
        'bytes', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: '<meta name="cover" content="cover-page"/>',
          coverItems: '<item id="cover-page" href="cover.xhtml" '
              'media-type="application/xhtml+xml"/>',
        ),
      );

      expect(await bookRef.readCoverBytes(), isNull);
    });

    // TC-COV-13 [Error guessing]: the cover is declared and classified as an
    // image, but the archive entry is missing — the case the try/catch exists
    // for, and the one that keeps its `on EpubException` honest now that the
    // catch is typed. A book with a broken cover must still be openable.
    test(
        'TC-COV-13 [Error guessing]: a declared cover missing from the '
        'archive yields null bytes rather than throwing', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: _coverMeta,
          coverItems: _coverImageItem,
          includeImageEntry: false,
        ),
      );

      expect(await bookRef.readCoverBytes(), isNull);
    });

    // TC-COV-14 [Equivalence partitioning]: the EPUB3 manifest convention
    // requires BOTH a cover-shaped name (id/`properties` of `cover` or
    // `cover-image`) AND an image media type — TC-COV-8 only ever tries items
    // that satisfy both at once. Here the sole image in the book satisfies
    // neither: it is a real image, but named nothing cover-like, so it must
    // not be picked up as the cover.
    test(
        'TC-COV-14 [Equivalence partitioning]: an image not named as a '
        'cover is not picked up as one', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          coverItems: '<item id="illustration" href="cover.png" '
              'media-type="image/png"/>',
        ),
      );

      expect(await bookRef.readCoverBytes(), isNull);
    });
  });
}
