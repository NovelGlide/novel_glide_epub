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
//   * In `_FileBytes`, `index < _windowStart` as `<=`, and
//     `_windowStart + _window.length` as `-`. Either reloads the window more
//     often than needed, from the same file, and returns the same bytes.
//   * In `_centralDirectoryOf`, deleting `input.position = end + 4`. The
//     search that found the end record last read its signature, which leaves
//     the position exactly there.
//   * In `_BoundedInputStream`'s `position` setter, `v > _size` as `>=`,
//     refusing a position exactly at the end. Every position set here, by
//     the reader or by `package:archive`, is read from at once, and that
//     read is refused at the end either way.
//
// Not equivalent, and not pinned: deleting `_ArchiveFileSource`'s
// `closeSync`. It leaks a file handle and changes nothing a read returns;
// counting a process's open handles is not portable, and suites running in
// the same process at once would make the count unreliable.
//
// Not equivalent, and pinned elsewhere: in `_InflatedBytes.add`,
// `<= _buffer.length` as `<`. An honest entry's last chunk then overflows
// its buffer and the entry is copied whole: the same bytes, held twice.
// Only memory shows it, and `epub_archive_memory_test.dart`'s TC-MEM-3
// does, in a process of its own.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart' show ListEquality;
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
    this.zip64LocalHeaderOffset,
  });

  /// A stored entry whose declared size is the truth.
  _CraftedZipEntry.stored(this.name, List<int> bytes)
      : method = _storeMethod,
        declaredUncompressedSize = bytes.length,
        payload = bytes,
        zeroRunLength = 0,
        zip64LocalHeaderOffset = null;

  final String name;
  final int method;
  final int declaredUncompressedSize;

  /// The bytes stored after the local header.
  final List<int> payload;

  /// Zero bytes stored after [payload]. `_craftZip` writes into a zero-filled
  /// buffer, so a run of hundreds of MiB costs no copy.
  final int zeroRunLength;

  /// When given, where the central directory says the local header is, in a
  /// zip64 extra field, as its 64 raw bits, instead of where `_craftZip`
  /// wrote it; `package:archive` reads it back as a signed value.
  final int? zip64LocalHeaderOffset;

  int get storedLength => payload.length + zeroRunLength;

  List<int> get zip64Sizes => <int>[
        if (zip64LocalHeaderOffset case final int offset) offset,
      ];

  int get extraLength => zip64Sizes.isEmpty ? 0 : 4 + 8 * zip64Sizes.length;
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
        entries[i].storedLength +
        entries[i].extraLength;
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
      ..setUint16(offset + 30, entry.extraLength, Endian.little)
      ..setUint32(
          offset + 42,
          _zip64Marked(entry.zip64LocalHeaderOffset, localHeaderOffsets[i]),
          Endian.little);
    offset += _centralFileHeaderLength;
    bytes.setAll(offset, names[i]);
    offset += names[i].length;
    _writeZip64Extra(data, offset, entry.zip64Sizes);
    offset += entry.extraLength;
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

/// A raw-deflate stream of about [length] bytes that inflates to nothing:
/// empty stored blocks, then a final one.
List<int> _emptyDeflateBlocks(int length) {
  const List<int> emptyBlock = <int>[0x00, 0x00, 0x00, 0xFF, 0xFF];
  const List<int> lastEmptyBlock = <int>[0x01, 0x00, 0x00, 0xFF, 0xFF];
  return <int>[
    for (int i = 0; i < length ~/ emptyBlock.length; i++) ...emptyBlock,
    ...lastEmptyBlock,
  ];
}

/// Writes a zip64 extended-information extra field holding [sizes] at [at];
/// nothing when there are none.
void _writeZip64Extra(ByteData data, int at, List<int> sizes) {
  if (sizes.isEmpty) {
    return;
  }
  data
    ..setUint16(at, 1, Endian.little) // zip64 extended information
    ..setUint16(at + 2, 8 * sizes.length, Endian.little);
  for (int i = 0; i < sizes.length; i++) {
    data.setUint64(at + 4 + 8 * i, sizes[i], Endian.little);
  }
}

/// The length of a [_sharedStreamZip] with a [payloadLength]-byte stream and
/// [recordCount] records without a zip64 extra field.
int _sharedStreamZipLength(int payloadLength, int recordCount) =>
    _localFileHeaderLength +
    1 +
    payloadLength +
    recordCount * (_centralFileHeaderLength + 1) +
    _endOfCentralDirectoryLength;

/// One entry's [payload] at the start of the file, and one central-directory
/// record for each of [compressedSizes], every record pointing at that one
/// entry and claiming its own compressed size: the overlapping-entry shape.
/// Each record declares 0 bytes uncompressed, so no declared-size limit can
/// react.
///
/// Given [zip64UncompressedSize] or [zip64CompressedSize], every record
/// carries that value in a zip64 extra field instead, its 32-bit field set
/// to 0xFFFFFFFF. A zip64 value is written as its 64 raw bits, and
/// `package:archive` reads it back as a signed value.
Uint8List _sharedStreamZip({
  required int method,
  required List<int> payload,
  required List<int> compressedSizes,
  int? zip64UncompressedSize,
  int? zip64CompressedSize,
}) {
  final List<int> zip64Sizes = <int>[
    if (zip64UncompressedSize != null) zip64UncompressedSize,
    if (zip64CompressedSize != null) zip64CompressedSize,
  ];
  final int extraLength = zip64Sizes.isEmpty ? 0 : 4 + 8 * zip64Sizes.length;
  final Uint8List bytes = Uint8List(
      _sharedStreamZipLength(payload.length, compressedSizes.length) +
          compressedSizes.length * extraLength);
  final ByteData data = ByteData.sublistView(bytes)
    ..setUint32(0, _localFileHeaderSignature, Endian.little)
    ..setUint16(4, 20, Endian.little) // version needed
    ..setUint16(8, method, Endian.little)
    ..setUint32(18, payload.length, Endian.little)
    ..setUint16(26, 1, Endian.little); // name length
  bytes
    ..[_localFileHeaderLength] = 0x78 // 'x'
    ..setAll(_localFileHeaderLength + 1, payload);

  final int directory = _localFileHeaderLength + 1 + payload.length;
  int at = directory;
  for (final int compressedSize in compressedSizes) {
    data
      ..setUint32(at, _centralFileHeaderSignature, Endian.little)
      ..setUint16(at + 4, 20, Endian.little) // version made by
      ..setUint16(at + 6, 20, Endian.little) // version needed
      ..setUint16(at + 10, method, Endian.little)
      ..setUint32(at + 20, _zip64Marked(zip64CompressedSize, compressedSize),
          Endian.little)
      ..setUint32(
          at + 24, _zip64Marked(zip64UncompressedSize, 0), Endian.little)
      ..setUint16(at + 28, 1, Endian.little) // name length
      ..setUint16(at + 30, extraLength, Endian.little)
      ..setUint32(at + 42, 0, Endian.little);
    bytes[at + _centralFileHeaderLength] = 0x78;
    at += _centralFileHeaderLength + 1;
    _writeZip64Extra(data, at, zip64Sizes);
    at += extraLength;
  }
  bytes.setAll(
    at,
    _endOfCentralDirectory(
      entryCount: compressedSizes.length,
      centralDirectoryLength: at - directory,
      centralDirectoryOffset: directory,
    ),
  );
  return bytes;
}

/// A record's 32-bit field: [plain], or 0xFFFFFFFF when [zip64Value] is
/// given, which sends a reader to the zip64 extra field for it.
int _zip64Marked(int? zip64Value, int plain) =>
    zip64Value == null ? plain : 0xFFFFFFFF;

/// Where the central-directory record of the entry [name] is in [zip], a
/// `_craftZip` result.
int _recordOf(Uint8List zip, String name) {
  final ByteData data = ByteData.sublistView(zip);
  final List<int> nameBytes = utf8.encode(name);
  int record = data.getUint32(
      zip.length - _endOfCentralDirectoryLength + 16, Endian.little);
  while (data.getUint16(record + 28, Endian.little) != nameBytes.length ||
      !const ListEquality<int>().equals(
          Uint8List.sublistView(zip, record + _centralFileHeaderLength,
              record + _centralFileHeaderLength + nameBytes.length),
          nameBytes)) {
    record += _centralFileHeaderLength +
        data.getUint16(record + 28, Endian.little) +
        data.getUint16(record + 30, Endian.little) +
        data.getUint16(record + 32, Endian.little);
  }
  return record;
}

/// Where the local header the central-directory [record] points at is in
/// [zip].
int _localHeaderOf(Uint8List zip, int record) =>
    ByteData.sublistView(zip).getUint32(record + 42, Endian.little);

/// [count] central-directory records, every one of an empty entry whose
/// local header is the one at offset 0, which has a name and an extra field
/// of 65,535 bytes each: a third of a MiB of file, whose local header costs
/// 128 KiB to parse each time a record leads to it.
Uint8List _sharedLocalHeaderZip(int count) {
  const int fieldLength = 0xFFFF;
  const int localLength = _localFileHeaderLength + 2 * fieldLength;
  final Uint8List records = _centralRecords(count);
  final Uint8List bytes =
      Uint8List(localLength + records.length + _endOfCentralDirectoryLength)
        ..fillRange(_localFileHeaderLength, localLength, 0x4E)
        ..setAll(localLength, records)
        ..setAll(
          localLength + records.length,
          _endOfCentralDirectory(
            entryCount: count,
            centralDirectoryLength: records.length,
            centralDirectoryOffset: localLength,
          ),
        );
  ByteData.sublistView(bytes)
    ..setUint32(0, _localFileHeaderSignature, Endian.little)
    ..setUint16(4, 20, Endian.little) // version needed
    ..setUint16(26, fieldLength, Endian.little)
    ..setUint16(28, fieldLength, Endian.little);
  return bytes;
}

/// [zip], a `_craftZip` result, with [tail] added to the end of its central
/// directory, and the end record's directory size grown to take it in.
Uint8List _withDirectoryTail(Uint8List zip, List<int> tail) {
  final int end = zip.length - _endOfCentralDirectoryLength;
  final ByteData original = ByteData.sublistView(zip, end);
  return Uint8List.fromList(<int>[
    ...zip.sublist(0, end),
    ...tail,
    ..._endOfCentralDirectory(
      entryCount: original.getUint16(10, Endian.little),
      centralDirectoryLength:
          original.getUint32(12, Endian.little) + tail.length,
      centralDirectoryOffset: original.getUint32(16, Endian.little),
    ),
  ]);
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

/// An entry that declares [declaredUncompressedSize] and stores nothing.
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

final Matcher _throwsCorrupt = throwsA(isA<EpubCorruptArchiveException>());

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

    // TC-LIM-3 [Boundary]: a file one byte over the limit is refused on its
    // size, which is checked before any of it is read. The file is a readable
    // ZIP, so only the size can refuse it.
    test(
        'TC-LIM-3 [Boundary]: a file one byte over the compressed-size limit '
        'is refused', () {
      final String path = sparseEmptyZip(_maxCompressedBytes + 1);

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
    // directory's records, whatever count the end record claims: here one.
    // The first local header is broken too, which opening does not read, so
    // 4097 records are refused as too many and 4096 decode.
    test(
        'TC-LIM-25 [Error guessing]: records are counted as they are read, '
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
          _throwsDecodedWithoutContainer);
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
    // to count, and are not a ZIP at all. Zeros are the case that matters:
    // read as an end record anyway, they describe an empty directory at
    // offset 0, and the file would open as a ZIP with no entries.
    test(
        'TC-LIM-28 [Error guessing]: bytes that are not a ZIP fail as a '
        'corrupt archive', () {
      expect(reader.openBook(Uint8List(64)..fillRange(0, 64, 0xAB)),
          _throwsCorrupt);
      expect(reader.openBook(Uint8List(64)), _throwsCorrupt);
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

    // TC-LIM-41 [Boundary]: a zip64 record at the very first byte, then the
    // records, the locator pointing at offset 0, and the end record. Offset
    // 0 is in the file, so the record is read there.
    test(
        'TC-LIM-41 [Boundary]: 4097 records behind a zip64 record at offset '
        '0 are refused', () {
      const int zip64RecordLength = 56;
      final Uint8List directory = _centralRecords(4097);
      final ByteData zip64Record = ByteData(zip64RecordLength)
        ..setUint32(0, 0x06064b50, Endian.little)
        ..setUint64(4, zip64RecordLength - 12, Endian.little)
        ..setUint64(24, 4097, Endian.little)
        ..setUint64(32, 4097, Endian.little)
        ..setUint64(40, directory.length, Endian.little)
        ..setUint64(48, zip64RecordLength, Endian.little);
      final ByteData tail = ByteData(20 + _endOfCentralDirectoryLength)
        ..setUint32(0, 0x07064b50, Endian.little)
        ..setUint64(8, 0, Endian.little)
        ..setUint32(16, 1, Endian.little)
        ..setUint32(20, _endOfCentralDirectorySignature, Endian.little)
        ..setUint16(20 + 4, 0xFFFF, Endian.little)
        ..setUint16(20 + 8, 0xFFFF, Endian.little)
        ..setUint16(20 + 10, 0xFFFF, Endian.little)
        ..setUint32(20 + 12, 0xFFFFFFFF, Endian.little)
        ..setUint32(20 + 16, 0xFFFFFFFF, Endian.little);

      expect(
          reader.openBook(Uint8List.fromList(<int>[
            ...zip64Record.buffer.asUint8List(),
            ...directory,
            ...tail.buffer.asUint8List(),
          ])),
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

  group('inflated sizes, counted when an entry is read', () {
    /// A readable book with [extra] entries nothing in it points at.
    Future<EpubBookRef> openWith(List<_CraftedZipEntry> extra) =>
        reader.openBook(_craftBook(
          chapter:
              _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
          extra: extra,
        ));

    List<int> read(EpubBookRef bookRef, String name) =>
        bookRef.epubArchive().findFile(name)!.content as List<int>;

    /// What is left of the whole-archive limit once a book has been opened
    /// and one entry at the per-entry limit read: opening inflates the
    /// documents it parses, which count like any other read. They are the
    /// same in every book `_craftBook` makes.
    late final int restLength;
    late final Uint8List restDeflated;

    setUpAll(() async {
      final EpubBookRef opened = await openWith(const <_CraftedZipEntry>[]);
      final int readAtOpen = <String>[
        'META-INF/container.xml',
        'OEBPS/content.opf',
        'OEBPS/toc.ncx',
      ].fold(0, (int sum, String name) => sum + read(opened, name).length);
      restLength = _maxTotalBytes - _maxEntryBytes - readAtOpen;
      restDeflated = _rawDeflateOf(restLength);
    });

    /// Entries that, read with the documents opening parses, inflate to
    /// exactly the whole-archive limit, and one byte more.
    List<_CraftedZipEntry> filledToTheLimit() => <_CraftedZipEntry>[
          _deflateEntry('half.bin', _deflateToEntryLimit,
              declaredUncompressedSize: _maxEntryBytes),
          _deflateEntry('rest.bin', restDeflated,
              declaredUncompressedSize: restLength),
          _deflateEntry('one.bin',
              _rawDeflateOf(1, block: Uint8List.fromList(<int>[0x4E])),
              declaredUncompressedSize: 1),
        ];

    // TC-LIM-8 [Error guessing]: the sizes entries declare are not held
    // against the limits, only the bytes they inflate to when read. A book
    // whose media entry honestly declares 300 MiB, which nothing in the book
    // points at, opens and reads whole; the entry itself is refused when it
    // is read.
    test(
        'TC-LIM-8 [Error guessing]: an entry honestly declaring 300 MiB does '
        'not stop the book, and is refused when it is read', () async {
      final Uint8List book = _craftBook(
        chapter:
            _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
        extra: <_CraftedZipEntry>[
          _deflateEntry('OEBPS/film.bin', _rawDeflateOf(300 * _oneMib),
              declaredUncompressedSize: 300 * _oneMib),
        ],
      );

      final EpubBookRef bookRef = await reader.openBook(book);
      expect((await reader.readBook(book)).chapters.single.htmlContent,
          _chapterXhtml);
      expect(() => read(bookRef, 'OEBPS/film.bin'), _throwsTooLarge);
    });

    // TC-LIM-9 [Boundary]: a declared size is only how large a buffer to
    // inflate into, and no larger than the limit allows. An entry declaring
    // 4 GiB and holding one byte opens, and reads as that byte.
    test(
        'TC-LIM-9 [Boundary]: an entry declaring 4 GiB that holds one byte '
        'reads as that byte', () async {
      final EpubBookRef bookRef = await openWith(const <_CraftedZipEntry>[
        _CraftedZipEntry(
          name: 'big.bin',
          method: _storeMethod,
          declaredUncompressedSize: 0xFFFFFFFE,
          payload: <int>[0x4E],
        ),
      ]);

      expect(bookRef.epubArchive().findFile('big.bin')!.size, 0xFFFFFFFE);
      expect(read(bookRef, 'big.bin'), <int>[0x4E]);
    });

    // TC-LIM-10 [Boundary]: entries each inside the per-entry limit whose
    // declared sizes add up to 600 MiB, past the whole-archive limit, and
    // which hold nothing. Nothing sums what they declare: the book opens,
    // and each reads as the nothing it holds.
    test(
        'TC-LIM-10 [Boundary]: entries declaring 600 MiB between them open '
        'and read as what they hold', () async {
      final EpubBookRef bookRef = await openWith(<_CraftedZipEntry>[
        for (int i = 0; i < 3; i++)
          _declaringEntry('part$i.bin', 200 * _oneMib),
      ]);

      for (int i = 0; i < 3; i++) {
        expect(read(bookRef, 'part$i.bin'), isEmpty);
      }
    });

    // TC-LIM-12 [Error guessing]: the lying header. The entry declares 1 KiB,
    // and nothing checks a declared size, so the book opens; read, it
    // inflates to one byte past the per-entry limit. Only counting while it
    // inflates can see it.
    test(
        'TC-LIM-12 [Error guessing]: a DEFLATE entry declaring 1 KiB that '
        'inflates one byte over the per-entry limit is refused when read',
        () async {
      final EpubBookRef bookRef = await openWith(<_CraftedZipEntry>[
        _deflateEntry('liar.bin', _deflateOneOverEntryLimit,
            declaredUncompressedSize: 1024),
      ]);

      expect(() => read(bookRef, 'liar.bin'), _throwsTooLarge);
    });

    // TC-LIM-13 [Boundary]: inflating to exactly the per-entry limit is
    // admissible, pinning `>` in the count.
    test(
        'TC-LIM-13 [Boundary]: a DEFLATE entry inflating to exactly the '
        'per-entry limit is read', () async {
      final EpubBookRef bookRef = await openWith(<_CraftedZipEntry>[
        _deflateEntry('atlimit.bin', _deflateToEntryLimit,
            declaredUncompressedSize: _maxEntryBytes),
      ]);

      expect(read(bookRef, 'atlimit.bin'), hasLength(_maxEntryBytes));
    });

    // TC-LIM-14 [Error guessing]: the canonical bomb, zeros declaring 1 KiB
    // and inflating to twice the per-entry limit, as the book's chapter.
    // Opening the book reads no chapter, so it opens; reading the chapter,
    // or reading the book whole, is abandoned once the count crosses the
    // limit, the bomb's tail never produced.
    test(
        'TC-LIM-14 [Error guessing]: a zeros bomb opens, and is refused when '
        'it is read', () async {
      final Uint8List bomb = _rawDeflateOf(2 * _maxEntryBytes);
      expect(bomb.length, lessThan(_oneMib));
      final Uint8List book = _craftBook(
          chapter: _deflateEntry(_chapterPath, bomb,
              declaredUncompressedSize: 1024));

      final EpubBookRef bookRef = await reader.openBook(book);
      expect(() => read(bookRef, _chapterPath), _throwsTooLarge);
      expect(reader.readBook(book), _throwsTooLarge);
    });

    // TC-LIM-15 [Boundary]: no entry reaches the per-entry limit, but the
    // third, lying about its size, pushes what the book's reads have
    // inflated past the whole-archive limit. Only the running total can
    // refuse it. The refused read adds nothing to the total, so a read that
    // fits in what is left is still read.
    test(
        'TC-LIM-15 [Boundary]: reads inflating to 656 MiB between them, none '
        'over the per-entry limit, are refused at the third, which uses up '
        'none of what is left', () async {
      final EpubBookRef bookRef = await openWith(<_CraftedZipEntry>[
        _deflateEntry('a.bin', _deflateToEntryLimit,
            declaredUncompressedSize: _maxEntryBytes),
        _deflateEntry('b.bin', _deflateTo200Mib,
            declaredUncompressedSize: 200 * _oneMib),
        _deflateEntry('c.bin', _deflateTo200Mib,
            declaredUncompressedSize: 1024),
        _CraftedZipEntry.stored('d.bin', const <int>[0x4E]),
      ]);

      expect(read(bookRef, 'a.bin'), hasLength(_maxEntryBytes));
      expect(read(bookRef, 'b.bin'), hasLength(200 * _oneMib));
      expect(() => read(bookRef, 'c.bin'), _throwsTooLarge);
      expect(read(bookRef, 'd.bin'), <int>[0x4E]);
    });

    // TC-LIM-16 [Boundary]: reads inflating to exactly the whole-archive
    // limit, the documents opening parsed included, are admissible. An
    // entry read twice is inflated and counted once: its second read is the
    // bytes kept from the first, and counting it again would push the next
    // read past the limit.
    test(
        'TC-LIM-16 [Boundary]: reads inflating to exactly the total limit are '
        'admissible, and a read twice is counted once', () async {
      final EpubBookRef bookRef = await openWith(filledToTheLimit());
      final List<int> half = read(bookRef, 'half.bin');

      expect(read(bookRef, 'half.bin'), same(half));
      expect(read(bookRef, 'rest.bin'), hasLength(restLength));
    });

    // TC-LIM-17 [Error guessing]: a stored entry is counted by the bytes it
    // really stores. It declares 1 KiB and stores one byte past the
    // per-entry limit.
    test(
        'TC-LIM-17 [Error guessing]: a STORE entry declaring 1 KiB that holds '
        'one byte over the per-entry limit is refused when read', () async {
      final EpubBookRef bookRef = await openWith(const <_CraftedZipEntry>[
        _CraftedZipEntry(
          name: 'liar.bin',
          method: _storeMethod,
          declaredUncompressedSize: 1024,
          zeroRunLength: _maxEntryBytes + 1,
        ),
      ]);

      expect(() => read(bookRef, 'liar.bin'), _throwsTooLarge);
    });

    // TC-LIM-18 [Boundary]: reads have inflated exactly the whole-archive
    // limit; one more byte is refused. The limit is the book's, counted
    // across the reads of one `EpubBookRef`: the same entry read from a
    // book newly opened is read.
    test(
        'TC-LIM-18 [Boundary]: a read one byte past what the total limit '
        'leaves is refused', () async {
      final EpubBookRef bookRef = await openWith(filledToTheLimit());
      read(bookRef, 'half.bin');
      read(bookRef, 'rest.bin');

      expect(() => read(bookRef, 'one.bin'), _throwsTooLarge);
      expect(read(await openWith(filledToTheLimit()), 'one.bin'), <int>[0x4E]);
    });
  });

  group('damaged containers', () {
    List<_CraftedZipEntry> oneEntry() => <_CraftedZipEntry>[
          _CraftedZipEntry.stored('NGE-SEED.txt', const <int>[0x4E]),
        ];

    // TC-LIM-37 [Error guessing]: a file cut short inside its end record.
    // No whole end record is left to read, so the file is refused as not a
    // ZIP rather than read past its end.
    for (final int cut in <int>[1, 3, 10, 17, 21]) {
      test(
          'TC-LIM-37 [Error guessing]: a file cut $cut bytes into its end '
          'record fails as a corrupt archive', () {
        final Uint8List zip = _craftZip(oneEntry());

        expect(reader.openBook(Uint8List.sublistView(zip, 0, zip.length - cut)),
            _throwsCorrupt);
      });
    }

    // TC-LIM-45 [Error guessing]: an end record's comment may hold anything,
    // the end record's own signature included. One in the comment's last
    // 21 bytes has no room for a whole record after it, so it is not taken
    // for one, and the ZIP opens.
    final Map<String, List<int>> commentByPlace = <String, List<int>>{
      'last four bytes': <int>[...utf8.encode('NGE-'), 0x50, 0x4B, 0x05, 0x06],
      '21 bytes from the end': <int>[
        0x50, 0x4B, 0x05, 0x06, //
        ...List<int>.filled(17, 0x4E),
      ],
    };
    for (final MapEntry<String, List<int>> comment in commentByPlace.entries) {
      test(
          'TC-LIM-45 [Error guessing]: a ZIP whose comment has the end record '
          'signature in its ${comment.key} opens', () {
        final Uint8List zip = _craftZip(oneEntry());
        ByteData.sublistView(zip)
            .setUint16(zip.length - 2, comment.value.length, Endian.little);

        expect(
            reader
                .openBook(Uint8List.fromList(<int>[...zip, ...comment.value])),
            _throwsDecodedWithoutContainer);
      });
    }

    // TC-LIM-38 [Boundary / error guessing]: the central directory has to
    // lie in the file. An offset past EOF, a size reaching one byte past it,
    // and a negative offset or size through zip64 are refused; a size
    // reaching exactly to EOF is not (the directory then takes in the end
    // record, whose signature ends the records).
    test(
        'TC-LIM-38 [Boundary]: a central directory placed outside the file '
        'fails as a corrupt archive', () {
      Uint8List patched(int Function(int length, int offset) sizeOf,
          {int offsetShift = 0}) {
        final Uint8List zip = _craftZip(oneEntry());
        final ByteData end = ByteData.sublistView(
            zip, zip.length - _endOfCentralDirectoryLength);
        final int offset = end.getUint32(16, Endian.little) + offsetShift;
        end
          ..setUint32(16, offset, Endian.little)
          ..setUint32(12, sizeOf(zip.length, offset), Endian.little);
        return zip;
      }

      expect(
          reader.openBook(
              patched((int length, int offset) => 46 + 12, offsetShift: 1000)),
          _throwsCorrupt);
      expect(
          reader.openBook(patched((int length, int offset) => length - offset)),
          _throwsDecodedWithoutContainer);
      expect(
          reader.openBook(
              patched((int length, int offset) => length - offset + 1)),
          _throwsCorrupt);

      Uint8List zip64With({int? size, int? offset}) {
        final Uint8List zip = _craftZip(oneEntry());
        final Uint8List zip64 = _withZip64EndRecord(zip);
        final ByteData record = ByteData.sublistView(
            zip64, zip.length - _endOfCentralDirectoryLength);
        if (size != null) {
          record.setInt64(40, size, Endian.little);
        }
        if (offset != null) {
          record.setInt64(48, offset, Endian.little);
        }
        return zip64;
      }

      expect(reader.openBook(zip64With(size: -1)), _throwsCorrupt);
      expect(reader.openBook(zip64With(offset: -1)), _throwsCorrupt);
    });

    // TC-LIM-39 [Boundary / error guessing]: the zip64 record the locator
    // points at has to be in the file, all 56 bytes of it. Past the file, or
    // negative, is refused. A zip64 record signature one byte too late for
    // the rest of the record to fit is refused too. The last place a record
    // fits is not: no zip64 record is there, so the end record's own values,
    // marked zip64 only by its disk field, are read instead.
    test(
        'TC-LIM-39 [Boundary]: a zip64 locator pointing where no zip64 record '
        'fits fails as a corrupt archive', () {
      Uint8List pointedAt(int Function(int length) recordAt,
          {bool signed = false}) {
        final Uint8List zip = _craftZip(oneEntry());
        final int record = zip.length - _endOfCentralDirectoryLength;
        final ByteData original = ByteData.sublistView(zip, record);
        final Uint8List zip64 = _withZip64EndRecord(
          zip,
          diskEntries: original.getUint16(8, Endian.little),
          size: original.getUint32(12, Endian.little),
          offset: original.getUint32(16, Endian.little),
        );
        final int pointed = recordAt(zip64.length);
        final ByteData data = ByteData.sublistView(zip64)
          ..setInt64(record + 56 + 8, pointed, Endian.little);
        if (signed) {
          data.setUint32(pointed, 0x06064b50, Endian.little);
        }
        return zip64;
      }

      expect(
          reader.openBook(pointedAt((int length) => length)), _throwsCorrupt);
      expect(reader.openBook(pointedAt((int length) => -1)), _throwsCorrupt);
      expect(
          reader.openBook(pointedAt((int length) => length - 55, signed: true)),
          _throwsCorrupt);
      expect(reader.openBook(pointedAt((int length) => length - 56)),
          _throwsDecodedWithoutContainer);
    });

    // TC-LIM-40 [Error guessing]: a central directory that ends in a few
    // stray bytes, too few for another record's signature, is read to its
    // last whole record and no further.
    test(
        'TC-LIM-40 [Error guessing]: stray bytes after the last directory '
        'record are ignored', () {
      expect(
          reader.openBook(_withDirectoryTail(
              _craftZip(oneEntry()), const <int>[0x4E, 0x47, 0x45])),
          _throwsDecodedWithoutContainer);
    });

    // TC-LIM-42 [Boundary]: a directory whose last record is cut short. A
    // signature with nothing after it, or with one byte less than a record's
    // 42-byte fixed part, is refused; with the whole fixed part (all zeros:
    // an empty entry at offset 0) it decodes.
    final Map<int, Matcher> outcomeByTailLength = <int, Matcher>{
      0: _throwsCorrupt,
      41: _throwsCorrupt,
      42: _throwsDecodedWithoutContainer,
    };
    for (final MapEntry<int, Matcher> tail in outcomeByTailLength.entries) {
      test(
          'TC-LIM-42 [Boundary]: a last record signature followed by '
          '${tail.key} bytes', () {
        final ByteData signature = ByteData(4)
          ..setUint32(0, _centralFileHeaderSignature, Endian.little);

        expect(
            reader.openBook(_withDirectoryTail(_craftZip(oneEntry()), <int>[
              ...signature.buffer.asUint8List(),
              ...List<int>.filled(tail.key, 0),
            ])),
            tail.value);
      });
    }
  });

  group('local headers, read with their entry', () {
    const String extraPath = 'OEBPS/extra.bin';

    /// A readable book with [extra] added, which nothing in it points at.
    Uint8List bookWith(_CraftedZipEntry extra) => _craftBook(
          chapter:
              _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
          extra: <_CraftedZipEntry>[extra],
        );

    /// The entry [name] of [book], opened and not yet read.
    Future<ArchiveFile> opened(Uint8List book, String name) async =>
        (await reader.openBook(book)).epubArchive().findFile(name)!;

    // TC-LIM-53 [Error guessing]: opening a book reads no entry's local
    // header, so a broken one in an entry the book never uses, a stray
    // `__MACOSX/` file here, neither stops the book opening nor stops it
    // being read whole. Read itself, the entry fails as a damaged container.
    test(
        'TC-LIM-53 [Error guessing]: a broken local header the book never '
        'uses fails only its own entry', () async {
      const String strayPath = '__MACOSX/OEBPS/._chapter1.xhtml';
      final Uint8List book = bookWith(
          _CraftedZipEntry.stored(strayPath, utf8.encode('NGE-SEED-STRAY')));
      ByteData.sublistView(book).setUint32(
          _localHeaderOf(book, _recordOf(book, strayPath)), 0, Endian.little);

      final ArchiveFile stray = await opened(book, strayPath);
      expect((await reader.readBook(book)).chapters.single.htmlContent,
          _chapterXhtml);
      expect(() => stray.content, _throwsCorrupt);
    });

    // TC-LIM-43 [Boundary]: the local header a record points at has to fit
    // in the file, its fixed 30 bytes at least. Negative, or with its
    // signature there but one byte short, fails the entry's read; the last
    // place it fits is read. The book opens either way.
    test(
        'TC-LIM-43 [Boundary]: a local header placed where it does not fit '
        'fails its entry when it is read', () async {
      final ArchiveFile negative = await opened(
          bookWith(const _CraftedZipEntry(
            name: extraPath,
            method: _storeMethod,
            declaredUncompressedSize: 0,
            zip64LocalHeaderOffset: -1,
          )),
          extraPath);
      expect(() => negative.content, _throwsCorrupt);

      Uint8List localHeaderAtEnd(int missing) {
        // The end record given a comment that is an empty local header, less
        // its last [missing] bytes, and the empty entry's record pointing at
        // it. With none missing it is the last place a local header fits;
        // with one, its signature is there but not its whole fixed part.
        final Uint8List zip =
            bookWith(_CraftedZipEntry.stored(extraPath, const <int>[]));
        final ByteData localHeader = ByteData(_localFileHeaderLength)
          ..setUint32(0, _localFileHeaderSignature, Endian.little)
          ..setUint16(4, 20, Endian.little);
        final Uint8List file = Uint8List.fromList(<int>[
          ...zip,
          ...localHeader.buffer
              .asUint8List(0, _localFileHeaderLength - missing),
        ]);
        ByteData.sublistView(file)
          ..setUint16(
              zip.length - 2, _localFileHeaderLength - missing, Endian.little)
          ..setUint32(
              _recordOf(zip, extraPath) + 42, zip.length, Endian.little);
        return file;
      }

      expect((await opened(localHeaderAtEnd(0), extraPath)).content, isEmpty);
      final ArchiveFile cut = await opened(localHeaderAtEnd(1), extraPath);
      expect(() => cut.content, _throwsCorrupt);
    });

    // TC-LIM-44 [Error guessing]: a streaming writer sets bit 3 of an entry's
    // flags and puts its sizes in a data descriptor after the data, which
    // `package:archive` reads after the compressed bytes. Compressed data
    // ending the file leaves the descriptor running off it; one byte longer,
    // the data itself does. Either fails the entry's read, before any read
    // runs past the end.
    final Map<String, int> overrunByCase = <String, int>{
      'ends the file': 0,
      'runs one byte past it': 1,
    };
    for (final MapEntry<String, int> overrun in overrunByCase.entries) {
      test(
          'TC-LIM-44 [Error guessing]: a bit-3 entry whose data '
          '${overrun.key} fails when it is read', () async {
        final Uint8List book =
            bookWith(_CraftedZipEntry.stored(extraPath, const <int>[0x4E]));
        final int record = _recordOf(book, extraPath);
        final int localHeader = _localHeaderOf(book, record);
        final int data = localHeader +
            _localFileHeaderLength +
            utf8.encode(extraPath).length;
        ByteData.sublistView(book)
          ..setUint16(localHeader + 6, 0x08, Endian.little)
          ..setUint16(record + 8, 0x08, Endian.little)
          ..setUint32(
              record + 20, book.length - data + overrun.value, Endian.little);

        final ArchiveFile extra = await opened(book, extraPath);
        expect(() => extra.content, _throwsCorrupt);
      });
    }

    // TC-LIM-54 [Error guessing]: 4096 records sharing one local header whose
    // name and extra field are 64 KiB each, the header's signature zeroed.
    // Opening reads no local header, so it gets as far as the missing
    // container; parsing that header, once or once for each record, would
    // fail it as a damaged container. TC-MEM-4, in
    // `epub_archive_memory_test.dart`, pins what opening it costs.
    test(
        'TC-LIM-54 [Error guessing]: 4096 records sharing one broken 128 KiB '
        'local header open without it being parsed', () {
      final Uint8List zip = _sharedLocalHeaderZip(_maxEntries);
      ByteData.sublistView(zip).setUint32(0, 0, Endian.little);

      expect(reader.openBook(zip), _throwsDecodedWithoutContainer);
    });
  });

  group('overlapping entries', () {
    // TC-LIM-33 [Error guessing]: the overlapping-entry bomb. 4096 records
    // share one 64 KiB DEFLATE stream of empty blocks, which inflates to
    // nothing, so no size limit reacts; only the compressed sizes their
    // records declare, adding up to far more than the file, can. Overlapping
    // entries are a damaged container, not a large one. Without that check
    // the book opens, and a book read whole inflates the stream 4096 times.
    test(
        'TC-LIM-33 [Error guessing]: 4096 records sharing one stream are '
        'refused', () {
      final List<int> stream = _emptyDeflateBlocks(64 * 1024);

      expect(
          reader.openBook(_sharedStreamZip(
            method: _deflateMethod,
            payload: stream,
            compressedSizes: List<int>.filled(_maxEntries, stream.length),
          )),
          _throwsCorrupt);
    });

    // TC-LIM-34 [Boundary]: compressed sizes adding up to exactly the file's
    // length are admissible, one byte more is not. Both stored records point
    // at the one entry; the second declares the bytes from its data to the
    // end of the file, and the first the local header's length or one byte
    // more.
    test(
        'TC-LIM-34 [Boundary]: compressed bytes adding up to the file length '
        'are decoded, one byte more refused', () {
      const List<int> payload = <int>[0x4E, 0x47, 0x45];
      const int dataStart = _localFileHeaderLength + 1;
      final int length = _sharedStreamZipLength(payload.length, 2);
      Uint8List zip(int firstSize) => _sharedStreamZip(
            method: _storeMethod,
            payload: payload,
            compressedSizes: <int>[firstSize, length - dataStart],
          );

      expect(reader.openBook(zip(dataStart)), _throwsDecodedWithoutContainer);
      expect(reader.openBook(zip(dataStart + 1)), _throwsCorrupt);
    });

    // TC-LIM-35 [Error guessing]: the same bomb with each record's compressed
    // size in a zip64 extra field, which `package:archive` reads as a signed
    // value: -1, and 2^62, which 4096 times over wraps to 0. Added up, either
    // would come to nothing past the file. A negative size is refused, and
    // 2^62 is past the file on its own, compared before it is added.
    final Map<String, int> zip64SizeByName = <String, int>{
      '-1': -1,
      '2^62': 1 << 62,
    };
    for (final MapEntry<String, int> size in zip64SizeByName.entries) {
      test(
          'TC-LIM-35 [Error guessing]: 4096 records sharing one 4 MiB stream, '
          'each claiming ${size.key} bytes through zip64, are refused', () {
        final List<int> stream = _emptyDeflateBlocks(4 * 1024 * 1024);

        expect(
            reader.openBook(_sharedStreamZip(
              method: _deflateMethod,
              payload: stream,
              compressedSizes: List<int>.filled(_maxEntries, 0),
              zip64CompressedSize: size.value,
            )),
            _throwsCorrupt);
      }, timeout: const Timeout(Duration(seconds: 10)));
    }

    // TC-LIM-36 [Boundary]: a zip64 size is read as a signed value, so a
    // record can declare a negative one, which no entry can really have and
    // which would pull the compressed total down, letting the rest of the
    // directory claim more of the file. Compressed or uncompressed, -1 is
    // refused as a damaged directory when the book is opened; 0 through the
    // same zip64 field is not.
    final Map<String, Uint8List Function(int)> zipBySize =
        <String, Uint8List Function(int)>{
      'compressed': (int size) => _sharedStreamZip(
            method: _storeMethod,
            payload: const <int>[],
            compressedSizes: const <int>[0],
            zip64CompressedSize: size,
          ),
      'uncompressed': (int size) => _sharedStreamZip(
            method: _storeMethod,
            payload: const <int>[],
            compressedSizes: const <int>[0],
            zip64UncompressedSize: size,
          ),
    };
    for (final MapEntry<String, Uint8List Function(int)> size
        in zipBySize.entries) {
      test(
          'TC-LIM-36 [Boundary]: a record declaring an ${size.key} size of -1 '
          'through zip64 is refused when the book is opened', () {
        expect(reader.openBook(size.value(0)), _throwsDecodedWithoutContainer);
        expect(reader.openBook(size.value(-1)), _throwsCorrupt);
      });
    }
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
    // or deflate. An entry compressed any other way does not stop the book
    // opening, and is refused when it is read.
    final Map<String, int> methodByName = <String, int>{
      'BZIP2': _bzip2Method,
      'LZMA': _lzmaMethod,
    };
    for (final MapEntry<String, int> method in methodByName.entries) {
      test(
          'TC-LIM-20 [EP]: a ${method.key} entry opens, and is refused when '
          'read', () async {
        final EpubBookRef bookRef = await reader.openBook(_craftBook(
          chapter: _CraftedZipEntry.stored(_chapterPath, chapterBytes),
          extra: <_CraftedZipEntry>[
            _CraftedZipEntry(
              name: 'OEBPS/extra.bin',
              method: method.value,
              declaredUncompressedSize: 3,
              payload: const <int>[0x4E, 0x47, 0x45],
            ),
          ],
        ));

        expect(() => bookRef.epubArchive().findFile('OEBPS/extra.bin')!.content,
            throwsA(isA<EpubUnsupportedCompressionException>()));
      });
    }

    // TC-LIM-23 [Error guessing]: an entry is inflated only when it is read,
    // so a corrupt one the book never reads does not stop it opening, or
    // being read whole; read itself, it fails as a damaged container.
    test(
        'TC-LIM-23 [Error guessing]: a corrupt DEFLATE entry the book never '
        'uses fails only when it is read', () async {
      final Uint8List book = _craftBook(
        chapter: _CraftedZipEntry.stored(_chapterPath, chapterBytes),
        extra: <_CraftedZipEntry>[
          _deflateEntry(
              'OEBPS/unused.bin', Uint8List(16)..fillRange(0, 16, 0xFF),
              declaredUncompressedSize: 16),
        ],
      );
      final EpubBookRef bookRef = await reader.openBook(book);

      expect((await reader.readBook(book)).chapters.single.htmlContent,
          _chapterXhtml);
      expect(() => bookRef.epubArchive().findFile('OEBPS/unused.bin')!.content,
          _throwsCorrupt);
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
    // one declaring more both read as exactly the bytes produced. The
    // entry's `size` is the size it declares, as `package:archive` gives it:
    // nothing has inflated the entry before it is read.
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

        expect(chapter.size, declared.value);
        expect(chapter.isCompressed, isFalse);
        expect(chapter.content, chapterBytes);
        expect(await (await bookRef.getChapters()).single.readHtmlContent(),
            _chapterXhtml);
      });
    }

    // TC-LIM-22 [Error guessing]: a corrupt DEFLATE stream — first block type
    // 3, which deflate reserves — as the chapter. The book opens, since
    // opening reads no chapter; reading the chapter, or the book whole, fails
    // as a corrupt archive, not as zlib's own FormatException.
    test(
        'TC-LIM-22 [Error guessing]: a corrupt DEFLATE chapter fails as a '
        'corrupt archive when it is read', () async {
      final Uint8List book = _craftBook(
        chapter: _deflateEntry(
            _chapterPath, Uint8List(16)..fillRange(0, 16, 0xFF),
            declaredUncompressedSize: 16),
      );
      final EpubBookRef bookRef = await reader.openBook(book);

      expect((await bookRef.getChapters()).single.readHtmlContent(),
          _throwsCorrupt);
      expect(reader.readBook(book), _throwsCorrupt);
    });
  });

  group('reads after opening', () {
    const String laterPath = 'OEBPS/later.bin';

    /// A final stored deflate block of [length] of the four bytes after it:
    /// the same nine bytes inflate to 2 or 4 bytes as [length] says, so an
    /// entry can be changed in place to inflate to another size.
    List<int> storedBlock(int length) => <int>[
          0x01, length, 0x00, 0xFF - length, 0xFF, //
          0x4E, 0x47, 0x45, 0x2D, // NGE-
        ];

    /// A readable book with one more entry, [later], that nothing in it
    /// points at.
    Uint8List bookWith(_CraftedZipEntry later) => _craftBook(
          chapter:
              _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
          extra: <_CraftedZipEntry>[later],
        );

    _CraftedZipEntry deflatedLater(List<int> payload) =>
        _deflateEntry(laterPath, Uint8List.fromList(payload),
            declaredUncompressedSize: 0);

    /// [bytes] with [from], which occurs in it once, replaced by [to].
    void replace(Uint8List bytes, List<int> from, List<int> to) {
      final int at = _indexOf(bytes, from);
      expect(_indexOf(bytes, from, at + 1), -1);
      bytes.setAll(at, to);
    }

    ArchiveFile later(EpubBookRef bookRef) =>
        bookRef.epubArchive().findFile(laterPath)!;

    // TC-LIM-46 [Scenario]: `openBook` reads no entry it does not parse; an
    // entry is read from the bytes when it is asked for. Changed after
    // opening, a stored entry reads as it is then.
    test(
        'TC-LIM-46 [Scenario]: an entry is read from the source when it is '
        'asked for, not when the book is opened', () async {
      final Uint8List bytes = bookWith(_CraftedZipEntry.stored(
          laterPath, utf8.encode('NGE-SEED-READ-LATER')));
      final EpubBookRef bookRef = await reader.openBook(bytes);
      replace(bytes, utf8.encode('NGE-SEED-READ-LATER'),
          utf8.encode('NGE-SEED-READ-AGAIN'));

      expect(later(bookRef).content, utf8.encode('NGE-SEED-READ-AGAIN'));
    });

    // TC-LIM-47 [Error guessing]: an entry is inflated only when it is read.
    // Damaged after opening, it fails no other read, and fails its own only
    // when it is read.
    test(
        'TC-LIM-47 [Error guessing]: an entry damaged after opening fails '
        'only when it is read', () async {
      final Uint8List bytes = bookWith(deflatedLater(storedBlock(4)));
      final EpubBookRef bookRef = await reader.openBook(bytes);
      replace(bytes, storedBlock(4), List<int>.filled(9, 0xFF));

      expect(await (await bookRef.getChapters()).single.readHtmlContent(),
          _chapterXhtml);
      expect(() => later(bookRef).content,
          throwsA(isA<EpubCorruptArchiveException>()));
    });

    // TC-LIM-48 [Scenario]: nothing about an entry's content is recorded
    // when the book is opened, so a read is of the bytes as they are then,
    // held only to the limits. Changed in place to inflate to fewer bytes,
    // or to more, the entry reads as it now is.
    test(
        'TC-LIM-48 [Scenario]: an entry changed after opening to inflate to '
        'fewer or more bytes reads as it now is', () async {
      final Uint8List shrinking = bookWith(deflatedLater(storedBlock(4)));
      final EpubBookRef shrunk = await reader.openBook(shrinking);
      replace(shrinking, storedBlock(4), storedBlock(2));

      final Uint8List growing = bookWith(deflatedLater(storedBlock(2)));
      final EpubBookRef grown = await reader.openBook(growing);
      replace(growing, storedBlock(2), storedBlock(4));

      expect(later(shrunk).content, utf8.encode('NG'));
      expect(later(grown).content, utf8.encode('NGE-'));
    });

    // TC-LIM-49 [Scenario]: an entry read once is kept, as `package:archive`
    // keeps it: read again, it is not read from the source again.
    test('TC-LIM-49 [Scenario]: an entry read once is not read again',
        () async {
      final Uint8List bytes = bookWith(deflatedLater(storedBlock(4)));
      final EpubBookRef bookRef = await reader.openBook(bytes);
      expect(later(bookRef).content, utf8.encode('NGE-'));
      replace(bytes, storedBlock(4), List<int>.filled(9, 0xFF));

      expect(later(bookRef).content, utf8.encode('NGE-'));
    });

    group('from a file', () {
      late Directory tempDir;
      late String path;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('nge_seed_later_');
        path = '${tempDir.path}/book.epub';
      });

      tearDown(() {
        tempDir.deleteSync(recursive: true);
      });

      // TC-LIM-50 [Error guessing]: a book file holds no handle once it is
      // open; each read opens the file again. Cut short by then, an entry
      // past the new end fails as a damaged container; gone, it fails as
      // the file system reports it.
      test(
          'TC-LIM-50 [Error guessing]: a file cut short or removed after '
          'opening fails the reads it breaks', () async {
        final Uint8List book = bookWith(deflatedLater(storedBlock(4)));
        File(path).writeAsBytesSync(book);
        final EpubBookRef cut = await reader.openBookFile(path);
        File(path).openSync(mode: FileMode.append)
          ..truncateSync(book.length ~/ 2)
          ..closeSync();

        expect(() => later(cut).content,
            throwsA(isA<EpubCorruptArchiveException>()));

        File(path).writeAsBytesSync(book);
        final EpubBookRef removed = await reader.openBookFile(path);
        File(path).deleteSync();
        expect(
            () => later(removed).content, throwsA(isA<FileSystemException>()));
      });

      // TC-LIM-51 [Scenario]: a file is read a window at a time, so headers
      // far apart, and an end record behind a long comment, are reached by
      // moving the window forwards and backwards. The book reads the same
      // from the file as from its bytes.
      test(
          'TC-LIM-51 [Scenario]: a book with headers far apart in its file '
          'reads as it does from its bytes', () async {
        final Random random = Random(0x4E47);
        final Uint8List big = Uint8List.fromList(
            List<int>.generate(300 * 1024, (int i) => random.nextInt(256)));
        final Uint8List zip = bookWith(_CraftedZipEntry.stored(laterPath, big));
        // A 60,000-byte comment the end record's signature cannot occur in.
        final Uint8List bytes =
            Uint8List.fromList(<int>[...zip, ...List<int>.filled(60000, 0x4E)]);
        ByteData.sublistView(bytes)
            .setUint16(zip.length - 2, 60000, Endian.little);
        File(path).writeAsBytesSync(bytes);

        final EpubBookRef fromFile = await reader.openBookFile(path);
        expect(fromFile, await reader.openBook(bytes));
        expect(later(fromFile).content, big);
        expect(await reader.readBookFile(path), await reader.readBook(bytes));
      });

      // TC-LIM-52 [Scenario]: a central directory of 4096 records, over
      // 200 KiB, is read from a file record by record, running across the
      // end of one window into the next many times. It decodes as it does
      // from bytes (TC-LIM-7).
      test(
          'TC-LIM-52 [Scenario]: a central directory spanning many windows '
          'of its file is read whole', () {
        File(path).writeAsBytesSync(_craftZip(<_CraftedZipEntry>[
          for (int i = 0; i < _maxEntries; i++)
            _CraftedZipEntry.stored('NGE-SEED-$i.txt', const <int>[]),
        ]));

        expect(reader.openBookFile(path), _throwsDecodedWithoutContainer);
      });
    });
  });
}

/// Where [pattern] first occurs in [bytes] from [start]; -1 when it does not.
int _indexOf(List<int> bytes, List<int> pattern, [int start = 0]) {
  for (int at = start; at <= bytes.length - pattern.length; at++) {
    if (const ListEquality<int>()
        .equals(bytes.sublist(at, at + pattern.length), pattern)) {
      return at;
    }
  }
  return -1;
}
