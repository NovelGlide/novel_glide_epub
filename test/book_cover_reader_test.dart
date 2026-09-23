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
/// absent. The seed PNG is archived under `OEBPS/[imageEntryName]`, and
/// [extraImages] adds further images by name.
Uint8List _buildCoverBook({
  String metaItems = '',
  String coverItems = '',
  bool includeImageEntry = true,
  String imageEntryName = 'cover.png',
  Map<String, List<int>> extraImages = const <String, List<int>>{},
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
        if (includeImageEntry) 'OEBPS/$imageEntryName': seedPngBytes(),
        for (final MapEntry<String, List<int>> image in extraImages.entries)
          'OEBPS/${image.key}': image.value,
      },
    );

const String _coverImageItem = '<item id="cover-img" href="cover.png" '
    'media-type="image/png"/>';
const String _coverMeta = '<meta name="cover" content="cover-img"/>';

/// The cover item with its archived name `封面.png` percent-encoded in the
/// href, as a URL-minded producer writes it.
const String _escapedCoverImageItem = '<item id="cover-img" '
    'href="%E5%B0%81%E9%9D%A2.png" media-type="image/png"/>';

/// The same escaped cover, flagged by the EPUB3 `cover-image` property
/// instead of an EPUB2 meta.
const String _escapedCoverPropertyItem = '<item id="img-1" '
    'href="%E5%B0%81%E9%9D%A2.png" media-type="image/png" '
    'properties="cover-image"/>';

/// Bytes declared as an image that are no image format at all.
final List<int> _notAnImage =
    'NGE-SEED these bytes are text, not any image format at all'.codeUnits;

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

    // TC-COV-15 [Regression]: the images map is keyed by decoded name, so a
    // cover whose manifest href escapes a non-ASCII name is found through
    // the decoded form of that href.
    test(
        'TC-COV-15 [Regression]: a cover with an escaped manifest href '
        'decodes', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: _coverMeta,
          coverItems: _escapedCoverImageItem,
          imageEntryName: '封面.png',
        ),
      );

      final Image? cover = await bookRef.readCover();

      expect(cover, isNotNull);
      expect(cover!.width, 2);
    });

    // TC-COV-16 [Equivalence partitioning]: the `cover` meta name and the
    // manifest id it names are each matched ignoring case, as real books
    // write `Cover` and `Cover-Img` as often as the lower-case forms.
    test(
        'TC-COV-16 [Equivalence partitioning]: the cover meta name and id '
        'match ignoring case', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: '<meta name="COVER" content="Cover-IMG"/>',
          coverItems: _coverImageItem,
        ),
      );

      expect(await bookRef.readCover(), isNotNull);
      expect(await bookRef.readCoverBytes(), seedPngBytes());
    });

    // TC-COV-17 [Error guessing]: the manifest declares an image cover the
    // archive does not carry. Unlike `readBookCoverBytes`, this path refuses
    // it with the archive-level exception.
    test(
        'TC-COV-17 [Error guessing]: a declared cover missing from the '
        'archive is rejected', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: _coverMeta,
          coverItems: _coverImageItem,
          includeImageEntry: false,
        ),
      );

      expect(
        bookRef.readCover,
        throwsA(isA<EpubMissingArchiveEntryException>()),
      );
    });

    // TC-COV-18 [Error guessing]: an image entry whose bytes are not an
    // image decodes to no cover rather than an exception.
    test(
        'TC-COV-18 [Error guessing]: cover bytes that do not decode yield '
        'no cover', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: '<meta name="cover" content="junk"/>',
          coverItems:
              '<item id="junk" href="junk.png" media-type="image/png"/>',
          extraImages: <String, List<int>>{
            'junk.png': _notAnImage,
          },
        ),
      );

      expect(await bookRef.readCover(), isNull);
      expect(await bookRef.readCoverBytes(), _notAnImage);
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
    // image, but the archive entry is missing — the one failure the narrow
    // `on EpubMissingArchiveEntryException` catch exists for. A book with a
    // broken cover must still be openable.
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

    // TC-COV-19 [Regression]: a cover whose manifest href escapes a
    // non-ASCII name is found by both conventions — the EPUB2 meta path and
    // the EPUB3 manifest path — through the decoded form of that href.
    for (final List<String> row in <List<String>>[
      <String>['the EPUB2 cover meta', _coverMeta, _escapedCoverImageItem],
      <String>[
        'the EPUB3 cover-image property',
        '',
        _escapedCoverPropertyItem,
      ],
    ]) {
      test(
          'TC-COV-19 [Regression]: an escaped cover href is found through '
          '${row[0]}', () async {
        final EpubBookRef bookRef = await const EpubReader().openBook(
          _buildCoverBook(
            metaItems: row[1],
            coverItems: row[2],
            imageEntryName: '封面.png',
          ),
        );

        expect(await bookRef.readCoverBytes(), seedPngBytes());
      });
    }

    // TC-COV-20 [Equivalence partitioning]: when both conventions name a
    // cover, the EPUB2 meta wins; when the meta names an id the manifest
    // lacks, the EPUB3 convention still finds one.
    test(
        'TC-COV-20 [Equivalence partitioning]: the cover meta takes '
        'precedence, and a dangling meta falls back to the manifest', () async {
      const List<int> otherBytes = <int>[0x4F, 0x54, 0x48];
      const String manifestCover = '<item id="cover" href="other.png" '
          'media-type="image/png"/>';
      final EpubBookRef both = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: _coverMeta,
          coverItems: '$manifestCover$_coverImageItem',
          extraImages: <String, List<int>>{'other.png': otherBytes},
        ),
      );
      final EpubBookRef dangling = await const EpubReader().openBook(
        _buildCoverBook(
          metaItems: '<meta name="cover" content="nge-seed-absent"/>',
          coverItems: manifestCover,
          extraImages: <String, List<int>>{'other.png': otherBytes},
        ),
      );

      expect(await both.readCoverBytes(), seedPngBytes());
      expect(await dangling.readCoverBytes(), otherBytes);
    });

    // TC-COV-21 [Equivalence partitioning]: the EPUB3 convention matches
    // the cover name and the image media type ignoring case, and passes over
    // a cover-named item that is not an image to a later one that is.
    test(
        'TC-COV-21 [Equivalence partitioning]: the manifest convention '
        'ignores case and skips a non-image cover item', () async {
      final EpubBookRef bookRef = await const EpubReader().openBook(
        _buildCoverBook(
          coverItems: '<item id="cover" href="cover.xhtml" '
              'media-type="application/xhtml+xml"/>'
              '<item id="img-1" href="cover.png" media-type="IMAGE/PNG" '
              'properties="COVER-IMAGE"/>',
        ),
      );

      expect(await bookRef.readCoverBytes(), seedPngBytes());
    });
  });
}
