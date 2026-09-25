// The ZIP container limits every `EpubReader` entry point enforces, and the
// single decode they are enforced in.
//
// Four limits, fixed inside the reader: 512 MiB of compressed input, 4096
// entries, 256 MiB inflated per entry, 512 MiB inflated in total. They are
// checked in two phases. The central directory's declared sizes and entry
// count are checked before anything is inflated; then every entry is inflated
// once, counting the bytes it really produces, and abandoned the moment they
// cross the per-entry limit or what the whole-archive limit has left. The
// second phase is what catches a header that lies about its size. A declared
// size is not held against the entry otherwise: writers get it wrong in good
// faith, so an entry inflating past what it declared opens when it stays
// within the limits.
//
// The limits are private, so every case goes through a public entry point and
// reads the outcome off what it throws: `EpubArchiveTooLargeException` for a
// refusal, and for an archive within the limits the first thing parsing trips
// over — most fixtures here have no `META-INF/container.xml`, so an archive
// that decoded reports `EpubMissingArchiveEntryException`.
//
// Meeting a 256 MiB boundary head-on means producing 256 MiB, so the fixtures
// are built to cost as little as that allows, and each trick is what a hostile
// archive does anyway:
//   * `_craftZip` writes the ZIP by hand, so an entry can declare any size in
//     the central directory whatever it really holds, and a stored run of
//     zeros is one zero-filled allocation rather than a copy.
//   * `_rawDeflateOf` streams a raw-deflate encoder over a reused 1 MiB block
//     of zeros, so a 256 MiB payload compresses to about a quarter of a
//     megabyte without ever being resident: the canonical bomb.
//
// Equivalent mutants, documented rather than chased:
//   * In `_inflateDeflate`, the input loop's `start < compressed.length` as
//     `<=`. The one extra pass it allows feeds zlib an empty range, which
//     produces nothing.
//   * In `_centralDirectoryOf`, deleting `input.position = end + 4`. The
//     search that found the end record last read its signature, which leaves
//     the position exactly there.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

const int _oneMib = 1024 * 1024;
const int _maxCompressedBytes = 512 * _oneMib;
const int _maxEntries = 4096;
const int _maxEntryBytes = 256 * _oneMib;
const int _maxTotalBytes = 512 * _oneMib;

const int _storeMethod = 0;
const int _deflateMethod = 8;
const int _bzip2Method = 12;

/// LZMA: a method ZIP defines and this parser has no inflater for.
const int _lzmaMethod = 14;

const int _localFileHeaderSignature = 0x04034b50;
const int _centralFileHeaderSignature = 0x02014b50;
const int _endOfCentralDirectorySignature = 0x06054b50;
const int _localFileHeaderLength = 30;
const int _centralFileHeaderLength = 46;
const int _endOfCentralDirectoryLength = 22;

/// Built on first use and shared, since each costs a pass over its whole
/// inflated length.
final Uint8List _deflateToEntryLimit = _rawDeflateOf(_maxEntryBytes);
final Uint8List _deflateOneOverEntryLimit = _rawDeflateOf(_maxEntryBytes + 1);
final Uint8List _deflateTo200Mib = _rawDeflateOf(200 * _oneMib);

/// One entry of a hand-crafted ZIP. [declaredUncompressedSize] goes into both
/// headers verbatim and is free to lie about what [payload] inflates to.
class _CraftedZipEntry {
  const _CraftedZipEntry({
    required this.name,
    required this.method,
    required this.declaredUncompressedSize,
    this.payload = const <int>[],
    this.zeroRunLength = 0,
  });

  /// A stored entry whose declared size is the truth.
  _CraftedZipEntry.stored(this.name, List<int> bytes)
      : method = _storeMethod,
        declaredUncompressedSize = bytes.length,
        payload = bytes,
        zeroRunLength = 0;

  final String name;
  final int method;
  final int declaredUncompressedSize;

  /// The bytes stored after the local header.
  final List<int> payload;

  /// Zero bytes stored after [payload]. `_craftZip` writes into a zero-filled
  /// buffer, so a run of hundreds of MiB costs no copy.
  final int zeroRunLength;

  int get storedLength => payload.length + zeroRunLength;
}

/// Assembles a ZIP byte for byte into one buffer: local headers and stored
/// bytes, the central directory, then the end-of-central-directory record.
/// `ZipEncoder` cannot stand in: it only writes truthful sizes.
Uint8List _craftZip(List<_CraftedZipEntry> entries) {
  final List<List<int>> names = <List<int>>[
    for (final _CraftedZipEntry entry in entries) utf8.encode(entry.name),
  ];
  int length = _endOfCentralDirectoryLength;
  for (int i = 0; i < entries.length; i++) {
    length += _localFileHeaderLength +
        _centralFileHeaderLength +
        2 * names[i].length +
        entries[i].storedLength;
  }
  final Uint8List bytes = Uint8List(length);
  final ByteData data = ByteData.sublistView(bytes);

  int offset = 0;
  final List<int> localHeaderOffsets = <int>[];
  for (int i = 0; i < entries.length; i++) {
    final _CraftedZipEntry entry = entries[i];
    localHeaderOffsets.add(offset);
    data
      ..setUint32(offset, _localFileHeaderSignature, Endian.little)
      ..setUint16(offset + 4, 20, Endian.little) // version needed
      ..setUint16(offset + 8, entry.method, Endian.little)
      ..setUint32(offset + 18, entry.storedLength, Endian.little)
      ..setUint32(offset + 22, entry.declaredUncompressedSize, Endian.little)
      ..setUint16(offset + 26, names[i].length, Endian.little);
    offset += _localFileHeaderLength;
    bytes.setAll(offset, names[i]);
    offset += names[i].length;
    bytes.setAll(offset, entry.payload);
    offset += entry.storedLength;
  }

  final int centralDirectoryOffset = offset;
  for (int i = 0; i < entries.length; i++) {
    final _CraftedZipEntry entry = entries[i];
    data
      ..setUint32(offset, _centralFileHeaderSignature, Endian.little)
      ..setUint16(offset + 4, 20, Endian.little) // version made by
      ..setUint16(offset + 6, 20, Endian.little) // version needed
      ..setUint16(offset + 10, entry.method, Endian.little)
      ..setUint32(offset + 20, entry.storedLength, Endian.little)
      ..setUint32(offset + 24, entry.declaredUncompressedSize, Endian.little)
      ..setUint16(offset + 28, names[i].length, Endian.little)
      ..setUint32(offset + 42, localHeaderOffsets[i], Endian.little);
    offset += _centralFileHeaderLength;
    bytes.setAll(offset, names[i]);
    offset += names[i].length;
  }

  bytes.setAll(
    offset,
    _endOfCentralDirectory(
      entryCount: entries.length,
      centralDirectoryLength: offset - centralDirectoryOffset,
      centralDirectoryOffset: centralDirectoryOffset,
    ),
  );
  return bytes;
}

Uint8List _endOfCentralDirectory({
  required int entryCount,
  required int centralDirectoryLength,
  required int centralDirectoryOffset,
}) {
  final ByteData record = ByteData(_endOfCentralDirectoryLength)
    ..setUint32(0, _endOfCentralDirectorySignature, Endian.little)
    ..setUint16(8, entryCount, Endian.little)
    ..setUint16(10, entryCount, Endian.little)
    ..setUint32(12, centralDirectoryLength, Endian.little)
    ..setUint32(16, centralDirectoryOffset, Endian.little);
  return record.buffer.asUint8List();
}

/// A readable, entry-less ZIP of exactly [length] bytes: zeros, then an empty
/// end-of-central-directory record. A ZIP reader looks for that record from
/// the end and ignores what precedes it, so only the compressed-size limit
/// can react to this fixture.
Uint8List _paddedEmptyZip(int length) {
  return Uint8List(length)
    ..setAll(
      length - _endOfCentralDirectoryLength,
      _endOfCentralDirectory(
        entryCount: 0,
        centralDirectoryLength: 0,
        centralDirectoryOffset: length - _endOfCentralDirectoryLength,
      ),
    );
}

/// [count] central-directory records and nothing else: no names, each with
/// [extraLength] and [commentLength] zero bytes of extra field and comment,
/// every one pointing at a local header at offset 0. Enough for the count,
/// which reads nothing of a record but its signature and lengths.
Uint8List _centralRecords(
  int count, {
  int extraLength = 0,
  int commentLength = 0,
}) {
  final int recordLength =
      _centralFileHeaderLength + extraLength + commentLength;
  final Uint8List bytes = Uint8List(count * recordLength);
  final ByteData data = ByteData.sublistView(bytes);
  for (int at = 0; at < bytes.length; at += recordLength) {
    data
      ..setUint32(at, _centralFileHeaderSignature, Endian.little)
      ..setUint16(at + 30, extraLength, Endian.little)
      ..setUint16(at + 32, commentLength, Endian.little);
  }
  return bytes;
}

/// [zip], a `_craftZip` result, with its end record in zip64 form: a zip64
/// end record holding the central directory's count, size and place, the
/// locator pointing at it, and an end record carrying [disk],
/// [diskEntries], [size] and [offset]. Any of them at its maximum tells a
/// reader to take the zip64 record's values instead; by default all are.
Uint8List _withZip64EndRecord(
  Uint8List zip, {
  int disk = 0xFFFF,
  int diskEntries = 0xFFFF,
  int size = 0xFFFFFFFF,
  int offset = 0xFFFFFFFF,
}) {
  const int zip64RecordLength = 56;
  const int locatorLength = 20;
  final int end = zip.length - _endOfCentralDirectoryLength;
  final ByteData original = ByteData.sublistView(zip, end);
  final int entryCount = original.getUint16(10, Endian.little);
  final ByteData tail =
      ByteData(zip64RecordLength + locatorLength + _endOfCentralDirectoryLength)
        ..setUint32(0, 0x06064b50, Endian.little)
        ..setUint64(4, zip64RecordLength - 12, Endian.little)
        ..setUint16(12, 45, Endian.little) // version made by
        ..setUint16(14, 45, Endian.little) // version needed
        ..setUint64(24, entryCount, Endian.little)
        ..setUint64(32, entryCount, Endian.little)
        ..setUint64(40, original.getUint32(12, Endian.little), Endian.little)
        ..setUint64(48, original.getUint32(16, Endian.little), Endian.little)
        ..setUint32(zip64RecordLength, 0x07064b50, Endian.little)
        ..setUint64(zip64RecordLength + 8, end, Endian.little)
        ..setUint32(zip64RecordLength + 16, 1, Endian.little); // disks
  const int endRecord = zip64RecordLength + locatorLength;
  tail
    ..setUint32(endRecord, _endOfCentralDirectorySignature, Endian.little)
    ..setUint16(endRecord + 4, disk, Endian.little)
    ..setUint16(endRecord + 8, diskEntries, Endian.little)
    ..setUint16(endRecord + 10, diskEntries, Endian.little)
    ..setUint32(endRecord + 12, size, Endian.little)
    ..setUint32(endRecord + 16, offset, Endian.little);
  return Uint8List.fromList(
      <int>[...zip.sublist(0, end), ...tail.buffer.asUint8List()]);
}

/// A raw-deflate stream (ZIP's DEFLATE method) inflating to exactly [length]
/// bytes of [block] repeated, zeros by default, fed to the encoder one block
/// at a time so the inflated form is never resident.
Uint8List _rawDeflateOf(int length, {Uint8List? block}) {
  final Uint8List unit = block ?? Uint8List(_oneMib);
  final RawZLibFilter filter = RawZLibFilter.deflateFilter(raw: true);
  final BytesBuilder out = BytesBuilder(copy: false);
  for (int remaining = length; remaining > 0; remaining -= unit.length) {
    filter.process(unit, 0, min(remaining, unit.length));
    for (List<int>? chunk = filter.processed(flush: false);
        chunk != null;
        chunk = filter.processed(flush: false)) {
      out.add(chunk);
    }
  }
  for (List<int>? chunk = filter.processed(end: true);
      chunk != null;
      chunk = filter.processed(end: true)) {
    out.add(chunk);
  }
  return out.takeBytes();
}

/// A DEFLATE entry declaring [declaredUncompressedSize], true or not.
_CraftedZipEntry _deflateEntry(
  String name,
  Uint8List payload, {
  required int declaredUncompressedSize,
}) {
  return _CraftedZipEntry(
    name: name,
    method: _deflateMethod,
    declaredUncompressedSize: declaredUncompressedSize,
    payload: payload,
  );
}

/// An entry that declares [declaredUncompressedSize] and stores nothing, for
/// the cases only the central directory is meant to see.
_CraftedZipEntry _declaringEntry(String name, int declaredUncompressedSize) {
  return _CraftedZipEntry(
    name: name,
    method: _storeMethod,
    declaredUncompressedSize: declaredUncompressedSize,
  );
}

const String _chapterPath = 'OEBPS/chapter1.xhtml';

/// A readable one-chapter EPUB 2 book, crafted so the chapter entry can use
/// any compression method: [chapter] is that entry. [extra] entries are added
/// to the archive and referenced by nothing.
Uint8List _craftBook({
  required _CraftedZipEntry chapter,
  List<_CraftedZipEntry> extra = const <_CraftedZipEntry>[],
}) {
  return _craftZip(<_CraftedZipEntry>[
    _CraftedZipEntry.stored('mimetype', utf8.encode('application/epub+zip')),
    _CraftedZipEntry.stored(
        'META-INF/container.xml',
        utf8.encode('<?xml version="1.0" encoding="UTF-8"?>'
            '<container version="1.0" '
            'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles>'
            '</container>')),
    _CraftedZipEntry.stored(
        'OEBPS/content.opf',
        utf8.encode('<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:NGE-SEED-LIMITS</dc:identifier>'
            '<dc:title>NGE-SEED Limits Book</dc:title>'
            '<dc:language>en</dc:language>'
            '</metadata>'
            '<manifest>'
            '<item id="ncx" href="toc.ncx" '
            'media-type="application/x-dtbncx+xml"/>'
            '<item id="ch1" href="chapter1.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine toc="ncx"><itemref idref="ch1"/></spine>'
            '</package>')),
    _CraftedZipEntry.stored(
        'OEBPS/toc.ncx',
        utf8.encode('<?xml version="1.0" encoding="UTF-8"?>'
            '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" '
            'version="2005-1">'
            '<head/><docTitle><text>NGE-SEED Limits Book</text></docTitle>'
            '<navMap><navPoint id="np-1" playOrder="1">'
            '<navLabel><text>NGE-SEED Chapter</text></navLabel>'
            '<content src="chapter1.xhtml"/>'
            '</navPoint></navMap>'
            '</ncx>')),
    chapter,
    ...extra,
  ]);
}

final String _chapterXhtml = seedXhtml('NGE-SEED-LIMITS-CH1');

/// A conventional book, zipped by `ZipEncoder` the way real tools write one.
Uint8List _buildConventionalBook() => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:NGE-SEED-PATH</dc:identifier>'
            '<dc:title>NGE-SEED Path Book</dc:title>'
            '<dc:creator>NGE-SEED Author</dc:creator>'
            '<meta name="cover" content="cover-img"/>'
            '</metadata>'
            '<manifest>'
            '<item id="ncx" href="toc.ncx" '
            'media-type="application/x-dtbncx+xml"/>'
            '<item id="ch1" href="chapter1.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<item id="cover-img" href="cover.png" media-type="image/png"/>'
            '</manifest>'
            '<spine toc="ncx"><itemref idref="ch1"/></spine>'
            '</package>',
        'OEBPS/toc.ncx': '<?xml version="1.0" encoding="UTF-8"?>'
            '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" '
            'version="2005-1">'
            '<head/><docTitle><text>NGE-SEED Path Book</text></docTitle>'
            '<navMap><navPoint id="np-1" playOrder="1">'
            '<navLabel><text>NGE-SEED Path Chapter</text></navLabel>'
            '<content src="chapter1.xhtml"/>'
            '</navPoint></navMap>'
            '</ncx>',
        _chapterPath: seedXhtml('NGE-SEED-PATH-CH1'),
      },
      binaryEntries: <String, List<int>>{'OEBPS/cover.png': seedPngBytes()},
    );

final Matcher _throwsTooLarge = throwsA(isA<EpubArchiveTooLargeException>());

/// The archive decoded within the limits; parsing then found no container.
final Matcher _throwsDecodedWithoutContainer =
    throwsA(isA<EpubMissingArchiveEntryException>());

void main() {
  const EpubReader reader = EpubReader();

  group('compressed-size limit, bytes entry points', () {
    // TC-LIM-1 [Boundary]: one byte past the limit. The fixture is a readable
    // ZIP, so only the compressed-size check can refuse it.
    test(
        'TC-LIM-1 [Boundary]: input one byte over the compressed-size limit '
        'is refused', () {
      expect(reader.openBook(_paddedEmptyZip(_maxCompressedBytes + 1)),
          _throwsTooLarge);
    });

    // TC-LIM-2 [Boundary]: exactly the limit is admissible, pinning `>`.
    test(
        'TC-LIM-2 [Boundary]: input of exactly the compressed-size limit is '
        'decoded', () {
      expect(reader.openBook(_paddedEmptyZip(_maxCompressedBytes)),
          _throwsDecodedWithoutContainer);
    });
  });

  group('compressed-size limit, file entry points', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('nge_seed_limits_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    /// A sparse file of [length] bytes ending in an empty ZIP's
    /// end-of-central-directory record: its size is real to `stat`, while
    /// the disk holds almost nothing.
    String sparseEmptyZip(int length) {
      final String path = '${tempDir.path}/sparse.epub';
      File(path).openSync(mode: FileMode.write)
        ..truncateSync(length)
        ..setPositionSync(length - _endOfCentralDirectoryLength)
        ..writeFromSync(_endOfCentralDirectory(
          entryCount: 0,
          centralDirectoryLength: 0,
          centralDirectoryOffset: length - _endOfCentralDirectoryLength,
        ))
        ..closeSync();
      return path;
    }

    // TC-LIM-3 [Boundary / error guessing]: a file one byte over the limit is
    // refused on its size alone. It is made unreadable first, so a reader
    // that opened it to find out would fail with FileSystemException instead.
    test(
        'TC-LIM-3 [Boundary]: a file one byte over the compressed-size limit '
        'is refused without being opened', () {
      final String path = sparseEmptyZip(_maxCompressedBytes + 1);
      final ProcessResult chmod = Process.runSync('chmod', <String>['0', path]);
      expect(chmod.exitCode, 0);
      // The premise: this process cannot open the file.
      expect(() => File(path).openSync(), throwsA(isA<FileSystemException>()));

      expect(reader.openBookFile(path), _throwsTooLarge);
      expect(reader.readBookFile(path), _throwsTooLarge);
    });

    // TC-LIM-4 [Boundary]: a file of exactly the limit is read and decoded.
    test(
        'TC-LIM-4 [Boundary]: a file of exactly the compressed-size limit is '
        'read and decoded', () {
      expect(reader.openBookFile(sparseEmptyZip(_maxCompressedBytes)),
          _throwsDecodedWithoutContainer);
    });

    // TC-LIM-5 [Scenario]: a conventional book opens the same through either
    // kind of entry point, both eagerly and by reference.
    test(
        'TC-LIM-5 [Scenario]: a book read from its file equals the same book '
        'read from its bytes', () async {
      final Uint8List bytes = _buildConventionalBook();
      final String path = '${tempDir.path}/book.epub';
      File(path).writeAsBytesSync(bytes);

      final EpubBook fromFile = await reader.readBookFile(path);
      expect(fromFile, await reader.readBook(bytes));
      expect(fromFile.title, 'NGE-SEED Path Book');
      expect(
          fromFile.chapters.single.htmlContent, seedXhtml('NGE-SEED-PATH-CH1'));
      expect(fromFile.coverImage, isNotNull);
      expect(await reader.openBookFile(path), await reader.openBook(bytes));
    });
  });

  group('entry-count limit', () {
    List<_CraftedZipEntry> emptyEntries(int count) => <_CraftedZipEntry>[
          for (int i = 0; i < count; i++)
            _CraftedZipEntry.stored('NGE-SEED-$i.txt', const <int>[]),
        ];

    // TC-LIM-6 [Boundary]: one entry past the limit, every entry empty, so
    // no size limit can be what refuses it.
    test('TC-LIM-6 [Boundary]: 4097 entries are refused', () {
      expect(reader.openBook(_craftZip(emptyEntries(_maxEntries + 1))),
          _throwsTooLarge);
    });

    // TC-LIM-7 [Boundary]: exactly the limit is admissible, pinning `>`.
    test('TC-LIM-7 [Boundary]: 4096 entries are decoded', () {
      expect(reader.openBook(_craftZip(emptyEntries(_maxEntries))),
          _throwsDecodedWithoutContainer);
    });

    // TC-LIM-25 [Error guessing]: the count is taken from the central
    // directory's records, before `package:archive` reads a single one. The
    // end record claims one entry, and the first local header is broken so
    // that reading the entries fails with ArchiveException: 4097 records are
    // refused as too many before that can happen, and 4096 get as far as it.
    test(
        'TC-LIM-25 [Error guessing]: records are counted before any is read, '
        'whatever count the end record claims', () {
      Uint8List lyingZip(int count) {
        final Uint8List zip = _craftZip(emptyEntries(count));
        ByteData.sublistView(zip)
          ..setUint32(0, 0, Endian.little)
          ..setUint16(
              zip.length - _endOfCentralDirectoryLength + 8, 1, Endian.little)
          ..setUint16(
              zip.length - _endOfCentralDirectoryLength + 10, 1, Endian.little);
        return zip;
      }

      expect(reader.openBook(lyingZip(_maxEntries + 1)), _throwsTooLarge);
      expect(reader.openBook(lyingZip(_maxEntries)),
          throwsA(isA<ArchiveException>()));
    });

    // TC-LIM-26 [Equivalence partitioning]: a zip64 end record moves the
    // central directory's place into the zip64 record, and the count follows
    // it there.
    test(
        'TC-LIM-26 [EP]: behind a zip64 end record, 4097 entries are refused '
        'and 4096 decoded', () {
      expect(
          reader.openBook(_withZip64EndRecord(_craftZip(emptyEntries(4097)))),
          _throwsTooLarge);
      expect(
          reader.openBook(_withZip64EndRecord(_craftZip(emptyEntries(4096)))),
          _throwsDecodedWithoutContainer);
    });

    // TC-LIM-27 [Error guessing]: an end record marked zip64 with no zip64
    // record behind it keeps its own values, as `package:archive` does, and
    // the count still walks the real directory.
    test(
        'TC-LIM-27 [Error guessing]: a zip64 marker with no zip64 record '
        'still has its 4097 entries refused', () {
      final Uint8List zip = _craftZip(emptyEntries(_maxEntries + 1));
      ByteData.sublistView(zip).setUint16(
          zip.length - _endOfCentralDirectoryLength + 8, 0xFFFF, Endian.little);

      expect(reader.openBook(zip), _throwsTooLarge);
    });

    // TC-LIM-28 [Error guessing]: bytes with no end record have no directory
    // to count; `package:archive` refuses them as it always has. The bytes
    // are not zeros, so reading them as an end record would not pass
    // quietly.
    test(
        'TC-LIM-28 [Error guessing]: bytes that are not a ZIP still fail '
        'with ArchiveException', () {
      expect(reader.openBook(Uint8List(64)..fillRange(0, 64, 0xAB)),
          throwsA(isA<ArchiveException>()));
    });

    // TC-LIM-29 [Error guessing]: a record's extra field and comment are part
    // of its length. Stepping over them wrongly would lose the next
    // record's signature and stop the count at one.
    test(
        'TC-LIM-29 [Error guessing]: 4097 records with extra fields and '
        'comments are refused', () {
      final Uint8List records =
          _centralRecords(4097, extraLength: 4, commentLength: 3);

      expect(
          reader.openBook(Uint8List.fromList(<int>[
            ...records,
            ..._endOfCentralDirectory(
              entryCount: 4097,
              centralDirectoryLength: records.length,
              centralDirectoryOffset: 0,
            ),
          ])),
          _throwsTooLarge);
    });

    // TC-LIM-30 [Error guessing]: an end record at the very first byte, with
    // the records after it. `package:archive` finds it all the same, so the
    // count has to as well.
    test(
        'TC-LIM-30 [Error guessing]: 4097 records behind an end record at '
        'offset 0 are refused', () {
      final Uint8List records = _centralRecords(4097);

      expect(
          reader.openBook(Uint8List.fromList(<int>[
            ..._endOfCentralDirectory(
              entryCount: 4097,
              centralDirectoryLength: records.length,
              centralDirectoryOffset: _endOfCentralDirectoryLength,
            ),
            ...records,
          ])),
          _throwsTooLarge);
    });

    // TC-LIM-31 [Error guessing]: a zip64 locator at the very first byte,
    // then the end record, the zip64 record, and the records. The locator
    // counts even there.
    test(
        'TC-LIM-31 [Error guessing]: 4097 records behind a zip64 locator at '
        'offset 0 are refused', () {
      const int zip64Record = 20 + _endOfCentralDirectoryLength;
      const int records = zip64Record + 56;
      final Uint8List directory = _centralRecords(4097);
      final ByteData head = ByteData(records)
        ..setUint32(0, 0x07064b50, Endian.little)
        ..setUint64(8, zip64Record, Endian.little)
        ..setUint32(16, 1, Endian.little)
        ..setUint32(20, _endOfCentralDirectorySignature, Endian.little)
        ..setUint16(20 + 4, 0xFFFF, Endian.little)
        ..setUint16(20 + 8, 0xFFFF, Endian.little)
        ..setUint16(20 + 10, 0xFFFF, Endian.little)
        ..setUint32(20 + 12, 0xFFFFFFFF, Endian.little)
        ..setUint32(20 + 16, 0xFFFFFFFF, Endian.little)
        ..setUint32(zip64Record, 0x06064b50, Endian.little)
        ..setUint64(zip64Record + 4, 44, Endian.little)
        ..setUint64(zip64Record + 24, 4097, Endian.little)
        ..setUint64(zip64Record + 32, 4097, Endian.little)
        ..setUint64(zip64Record + 40, directory.length, Endian.little)
        ..setUint64(zip64Record + 48, records, Endian.little);

      expect(
          reader.openBook(Uint8List.fromList(
              <int>[...head.buffer.asUint8List(), ...directory])),
          _throwsTooLarge);
    });

    // TC-LIM-32 [Equivalence partitioning]: any one of the end record's four
    // fields at its maximum sends a reader to the zip64 record. Here the end
    // record's own fields describe an empty directory, and only the zip64
    // record points at the 4097 real ones.
    final Map<String, Uint8List Function(Uint8List)> zip64ByMarker =
        <String, Uint8List Function(Uint8List)>{
      'disk': (Uint8List zip) =>
          _withZip64EndRecord(zip, diskEntries: 0, size: 0, offset: 0),
      'entry count': (Uint8List zip) =>
          _withZip64EndRecord(zip, disk: 0, size: 0, offset: 0),
      'size': (Uint8List zip) =>
          _withZip64EndRecord(zip, disk: 0, diskEntries: 0, offset: 0),
      'offset': (Uint8List zip) =>
          _withZip64EndRecord(zip, disk: 0, diskEntries: 0, size: 0),
    };
    for (final MapEntry<String, Uint8List Function(Uint8List)> marker
        in zip64ByMarker.entries) {
      test(
          'TC-LIM-32 [EP]: an end record whose ${marker.key} alone marks '
          'zip64 has the zip64 record counted', () {
        expect(reader.openBook(marker.value(_craftZip(emptyEntries(4097)))),
            _throwsTooLarge);
      });
    }
  });

  group('declared sizes, before inflating', () {
    // TC-LIM-8 [Boundary]: an entry declaring one byte past the per-entry
    // limit and storing nothing. There is nothing to inflate, so only the
    // central directory check can refuse it.
    test(
        'TC-LIM-8 [Boundary]: an entry declaring one byte over the per-entry '
        'limit is refused', () {
      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            _declaringEntry('big.bin', _maxEntryBytes + 1),
          ])),
          _throwsTooLarge);
    });

    // TC-LIM-9 [Boundary]: exactly the per-entry limit is admissible.
    test(
        'TC-LIM-9 [Boundary]: an entry declaring exactly the per-entry limit '
        'is decoded', () {
      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            _declaringEntry('big.bin', _maxEntryBytes),
          ])),
          _throwsDecodedWithoutContainer);
    });

    // TC-LIM-10 [Boundary]: entries each well inside the per-entry limit
    // whose declared sizes add up past the total, so only the sum can refuse.
    test(
        'TC-LIM-10 [Boundary]: entries declaring 600 MiB between them are '
        'refused', () {
      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            for (int i = 0; i < 3; i++)
              _declaringEntry('part$i.bin', 200 * _oneMib),
          ])),
          _throwsTooLarge);
    });

    // TC-LIM-11 [Boundary]: a declared total of exactly the limit is
    // admissible.
    test(
        'TC-LIM-11 [Boundary]: entries declaring exactly the total limit '
        'between them are decoded', () {
      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            for (int i = 0; i < 2; i++)
              _declaringEntry('half$i.bin', _maxTotalBytes ~/ 2),
          ])),
          _throwsDecodedWithoutContainer);
    });
  });

  group('inflated sizes, counted while inflating', () {
    // TC-LIM-12 [Error guessing]: the lying header. The entry declares 1 KiB,
    // which the directory check accepts, and inflates to one byte past the
    // per-entry limit. Only counting during the inflate can see it.
    test(
        'TC-LIM-12 [Error guessing]: a DEFLATE entry declaring 1 KiB that '
        'inflates one byte over the per-entry limit is refused', () {
      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            _deflateEntry('liar.bin', _deflateOneOverEntryLimit,
                declaredUncompressedSize: 1024),
          ])),
          _throwsTooLarge);
    });

    // TC-LIM-13 [Boundary]: inflating to exactly the per-entry limit is
    // admissible, pinning `>` in the inflate-time count.
    test(
        'TC-LIM-13 [Boundary]: a DEFLATE entry inflating to exactly the '
        'per-entry limit is decoded', () {
      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            _deflateEntry('atlimit.bin', _deflateToEntryLimit,
                declaredUncompressedSize: _maxEntryBytes),
          ])),
          _throwsDecodedWithoutContainer);
    });

    // TC-LIM-14 [Error guessing]: the canonical bomb, zeros declaring 1 KiB
    // and inflating to twice the per-entry limit, is abandoned once the
    // count crosses the limit; its tail is never produced.
    test(
        'TC-LIM-14 [Error guessing]: a zeros bomb inflating to twice the '
        'per-entry limit is refused', () {
      final Uint8List bomb = _rawDeflateOf(2 * _maxEntryBytes);
      expect(bomb.length, lessThan(_oneMib));

      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            _deflateEntry('bomb.bin', bomb, declaredUncompressedSize: 1024),
          ])),
          _throwsTooLarge);
    });

    // TC-LIM-15 [Boundary]: no entry reaches the per-entry limit, but the
    // third, lying about its size, pushes the running total past the
    // whole-archive limit. Only the total can refuse it.
    test(
        'TC-LIM-15 [Boundary]: entries inflating to 656 MiB between them, '
        'none over the per-entry limit, are refused', () {
      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            _deflateEntry('a.bin', _deflateToEntryLimit,
                declaredUncompressedSize: _maxEntryBytes),
            _deflateEntry('b.bin', _deflateTo200Mib,
                declaredUncompressedSize: 200 * _oneMib),
            _deflateEntry('c.bin', _deflateTo200Mib,
                declaredUncompressedSize: 1024),
          ])),
          _throwsTooLarge);
    });

    // TC-LIM-16 [Boundary]: inflating to exactly the total limit is
    // admissible, pinning `>` against what the total leaves.
    test(
        'TC-LIM-16 [Boundary]: entries inflating to exactly the total limit '
        'are decoded', () {
      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            for (int i = 0; i < 2; i++)
              _deflateEntry('half$i.bin', _deflateToEntryLimit,
                  declaredUncompressedSize: _maxEntryBytes),
          ])),
          _throwsDecodedWithoutContainer);
    });

    // TC-LIM-17 [Error guessing]: a stored entry is counted by the bytes it
    // really stores. It declares 1 KiB and stores one byte past the
    // per-entry limit.
    test(
        'TC-LIM-17 [Error guessing]: a STORE entry declaring 1 KiB that holds '
        'one byte over the per-entry limit is refused', () {
      expect(
          reader.openBook(_craftZip(const <_CraftedZipEntry>[
            _CraftedZipEntry(
              name: 'liar.bin',
              method: _storeMethod,
              declaredUncompressedSize: 1024,
              zeroRunLength: _maxEntryBytes + 1,
            ),
          ])),
          _throwsTooLarge);
    });

    // TC-LIM-18 [Boundary]: two entries use the whole total; a third,
    // declaring nothing, inflates to a single byte, one over what is left.
    test(
        'TC-LIM-18 [Boundary]: an entry one byte past what the total limit '
        'leaves is refused', () {
      expect(
          reader.openBook(_craftZip(<_CraftedZipEntry>[
            for (int i = 0; i < 2; i++)
              _deflateEntry('half$i.bin', _deflateToEntryLimit,
                  declaredUncompressedSize: _maxEntryBytes),
            _deflateEntry('extra.bin',
                _rawDeflateOf(1, block: Uint8List.fromList(<int>[0x4E])),
                declaredUncompressedSize: 0),
          ])),
          _throwsTooLarge);
    });
  });

  group('the one decode', () {
    // TC-LIM-19 [Equivalence partitioning]: each compression method an EPUB
    // may use produces the chapter it holds.
    final Uint8List chapterBytes = utf8.encode(_chapterXhtml);
    final Map<String, _CraftedZipEntry> chapterByMethod =
        <String, _CraftedZipEntry>{
      'STORE': _CraftedZipEntry.stored(_chapterPath, chapterBytes),
      'DEFLATE': _deflateEntry(
          _chapterPath, _rawDeflateOf(chapterBytes.length, block: chapterBytes),
          declaredUncompressedSize: chapterBytes.length),
    };
    for (final MapEntry<String, _CraftedZipEntry> method
        in chapterByMethod.entries) {
      test('TC-LIM-19 [EP]: a ${method.key} chapter reads back as written',
          () async {
        final EpubBook book =
            await reader.readBook(_craftBook(chapter: method.value));

        expect(book.chapters.single.htmlContent, _chapterXhtml);
      });
    }

    // TC-LIM-20 [Equivalence partitioning]: an EPUB container may only store
    // or deflate. Any other method refuses the book when it is opened, even
    // for an entry nothing in the book points at.
    final Map<String, int> methodByName = <String, int>{
      'BZIP2': _bzip2Method,
      'LZMA': _lzmaMethod,
    };
    for (final MapEntry<String, int> method in methodByName.entries) {
      test(
          'TC-LIM-20 [EP]: an unused ${method.key} entry refuses the book at '
          'open', () {
        expect(
            reader.openBook(_craftBook(
              chapter: _CraftedZipEntry.stored(_chapterPath, chapterBytes),
              extra: <_CraftedZipEntry>[
                _CraftedZipEntry(
                  name: 'OEBPS/extra.bin',
                  method: method.value,
                  declaredUncompressedSize: 3,
                  payload: const <int>[0x4E, 0x47, 0x45],
                ),
              ],
            )),
            throwsA(isA<EpubMissingArchiveEntryException>()));
      });
    }

    // TC-LIM-23 [Error guessing]: every entry is inflated at open, so a
    // corrupt one fails the open even when the book never reads it.
    test(
        'TC-LIM-23 [Error guessing]: a corrupt DEFLATE entry the book never '
        'uses fails the open', () {
      expect(
          reader.openBook(_craftBook(
            chapter: _CraftedZipEntry.stored(_chapterPath, chapterBytes),
            extra: <_CraftedZipEntry>[
              _deflateEntry(
                  'OEBPS/unused.bin', Uint8List(16)..fillRange(0, 16, 0xFF),
                  declaredUncompressedSize: 16),
            ],
          )),
          throwsA(isA<FormatException>()));
    });

    // TC-LIM-24 [Error guessing]: a DEFLATE stream cut short is accepted as
    // what it holds, a strict prefix of the whole; zlib reports no error for
    // it. `package:archive`'s own inflate behaves the same, so books that
    // opened before still open. Pinned so a change either way is seen.
    test(
        'TC-LIM-24 [Error guessing]: a truncated DEFLATE chapter opens with '
        'the part it holds', () async {
      final Uint8List whole = Uint8List.fromList(<int>[
        for (int i = 0; i < 200; i++) ...utf8.encode('NGE-SEED line $i\n'),
      ]);
      final Uint8List compressed = _rawDeflateOf(whole.length, block: whole);
      final EpubBookRef bookRef = await reader.openBook(_craftBook(
        chapter: _deflateEntry(_chapterPath,
            Uint8List.sublistView(compressed, 0, compressed.length ~/ 2),
            declaredUncompressedSize: whole.length),
      ));
      final List<int> content =
          bookRef.epubArchive().findFile(_chapterPath)!.content as List<int>;

      expect(content.length, inInclusiveRange(1, whole.length - 1));
      expect(content, whole.sublist(0, content.length));
    });

    // TC-LIM-21 [Equivalence partitioning]: an entry's declared size is not
    // held against it. One declaring less than it inflates to — as
    // `package:archive`'s `ArchiveFile.string` writes non-ASCII text — and
    // one declaring more both open, holding exactly the bytes produced.
    final Map<String, int> declaredByCase = <String, int>{
      'less': 1,
      'more': chapterBytes.length + 100,
    };
    for (final MapEntry<String, int> declared in declaredByCase.entries) {
      test(
          'TC-LIM-21 [EP]: a chapter declaring ${declared.key} than it '
          'inflates to opens with its real content', () async {
        final EpubBookRef bookRef = await reader.openBook(_craftBook(
          chapter: _deflateEntry(_chapterPath,
              _rawDeflateOf(chapterBytes.length, block: chapterBytes),
              declaredUncompressedSize: declared.value),
        ));
        final ArchiveFile chapter =
            bookRef.epubArchive().findFile(_chapterPath)!;

        expect(chapter.size, chapterBytes.length);
        expect(chapter.isCompressed, isFalse);
        expect(chapter.content, chapterBytes);
        expect(await (await bookRef.getChapters()).single.readHtmlContent(),
            _chapterXhtml);
      });
    }

    // TC-LIM-22 [Error guessing]: a corrupt DEFLATE stream — first block type
    // 3, which deflate reserves — fails opening with an Exception a caller
    // catching `on Exception` sees, not an Error. The parser maps nothing
    // here into EpubException, so zlib's FormatException is what arrives.
    test(
        'TC-LIM-22 [Error guessing]: a corrupt DEFLATE entry fails with '
        'FormatException, an Exception', () {
      expect(
          reader.openBook(_craftBook(
            chapter: _deflateEntry(
                _chapterPath, Uint8List(16)..fillRange(0, 16, 0xFF),
                declaredUncompressedSize: 16),
          )),
          throwsA(allOf(isA<Exception>(), isA<FormatException>())));
    });
  });
}
