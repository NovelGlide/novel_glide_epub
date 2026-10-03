// The limits are the caller's: every entry point takes them, and `null` sets
// none. Unless a case is about passing none, or passing a bad one, this suite
// passes 256 MiB for one entry and 512 MiB for one `readBook`, and reads the
// outcome off what the call throws: `EpubArchiveTooLargeException` for a
// refusal, and for an archive within the limits the first thing parsing trips
// over — many fixtures here have no `META-INF/container.xml`, so an archive
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
// `<= _buffer.length` as `<`; and in `_inflate`, `inflater == null` as
// `!=`, or its two branches swapped, which bounds a deflated entry's buffer
// by its compressed length. Either way an honest entry overflows its buffer
// and is copied whole: the same bytes, held twice. Only memory shows it, and
// `epub_archive_memory_test.dart`'s TC-MEM-3, TC-MEM-5 and TC-MEM-10 do, in
// a process of their own, which the mutation run's per-test coverage cannot
// trace back to these lines.
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart' show ListEquality;
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_text_content_file_ref.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

const int _oneMib = 1024 * 1024;

/// The limits this suite passes: for one entry, and for one `readBook`.
const int _maxEntryBytes = 256 * _oneMib;
const int _maxTotalBytes = 512 * _oneMib;

/// A file past 512 MiB, and more than 4096 entries: neither size nor count
/// stops a book from opening.
const int _largeFileLength = 600 * _oneMib;
const int _manyEntries = 10000;

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
    this.zip64UncompressedSize,
    this.zip64LocalHeaderOffset,
  });

  /// A stored entry whose declared size is the truth.
  _CraftedZipEntry.stored(this.name, List<int> bytes)
      : method = _storeMethod,
        declaredUncompressedSize = bytes.length,
        payload = bytes,
        zeroRunLength = 0,
        zip64UncompressedSize = null,
        zip64LocalHeaderOffset = null;

  final String name;
  final int method;
  final int declaredUncompressedSize;

  /// The bytes stored after the local header.
  final List<int> payload;

  /// Zero bytes stored after [payload]. `_craftZip` writes into a zero-filled
  /// buffer, so a run of hundreds of MiB costs no copy.
  final int zeroRunLength;

  /// When given, the uncompressed size the central directory declares in a
  /// zip64 extra field, as its 64 raw bits, instead of
  /// [declaredUncompressedSize].
  final int? zip64UncompressedSize;

  /// When given, where the central directory says the local header is, in a
  /// zip64 extra field, as its 64 raw bits, instead of where `_craftZip`
  /// wrote it; `package:archive` reads it back as a signed value.
  final int? zip64LocalHeaderOffset;

  int get storedLength => payload.length + zeroRunLength;

  /// The zip64 extra field's values, in the order the field holds them.
  List<int> get zip64Sizes => <int>[
        if (zip64UncompressedSize case final int size) size,
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
      ..setUint32(
          offset + 24,
          _zip64Marked(
              entry.zip64UncompressedSize, entry.declaredUncompressedSize),
          Endian.little)
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
/// Each record declares 0 bytes uncompressed.
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

/// A ZIP's local headers, data and central directory, without its end
/// record, and what that record says of the directory.
class _ZipBody {
  const _ZipBody(
    this.body, {
    required this.directoryOffset,
    required this.directoryLength,
    required this.entryCount,
  });

  final Uint8List body;
  final int directoryOffset;
  final int directoryLength;
  final int entryCount;
}

/// The body of [zip], a `_craftZip` result, laid out to start at [at] in
/// another file: every record's local-header offset moved by [at]. The
/// directory's place is given in that file.
_ZipBody _bodyAt(Uint8List zip, int at) {
  final int end = zip.length - _endOfCentralDirectoryLength;
  final ByteData original = ByteData.sublistView(zip, end);
  final int entryCount = original.getUint16(10, Endian.little);
  final int directoryLength = original.getUint32(12, Endian.little);
  final int directoryOffset = original.getUint32(16, Endian.little);
  final Uint8List body = zip.sublist(0, end);
  final ByteData data = ByteData.sublistView(body);
  for (int record = directoryOffset, i = 0; i < entryCount; i++) {
    data.setUint32(record + 42, data.getUint32(record + 42, Endian.little) + at,
        Endian.little);
    record += _centralFileHeaderLength +
        data.getUint16(record + 28, Endian.little) +
        data.getUint16(record + 30, Endian.little) +
        data.getUint16(record + 32, Endian.little);
  }
  return _ZipBody(
    body,
    directoryOffset: at + directoryOffset,
    directoryLength: directoryLength,
    entryCount: entryCount,
  );
}

/// [zip], a `_craftZip` result, as it is laid out from [at] on in a file
/// whose first [at] bytes no entry holds: its entries, their directory and
/// its end record, moved up by [at].
Uint8List _movedTo(Uint8List zip, int at) {
  final _ZipBody(
    :Uint8List body,
    :int directoryOffset,
    :int directoryLength,
    :int entryCount
  ) = _bodyAt(zip, at);
  return Uint8List.fromList(<int>[
    ...body,
    ..._endOfCentralDirectory(
      entryCount: entryCount,
      centralDirectoryLength: directoryLength,
      centralDirectoryOffset: directoryOffset,
    ),
  ]);
}

/// [zip], a `_craftZip` result, after [gap] zero bytes that no entry holds.
/// A `Uint8List` is zero-filled when it is made, so the gap costs no
/// writing, and nothing reads it.
Uint8List _afterGap(Uint8List zip, int gap) {
  final Uint8List moved = _movedTo(zip, gap);
  return Uint8List(gap + moved.length)..setAll(gap, moved);
}

/// [zip], a `_craftZip` result without extra fields, with an extra field of
/// [extraLength] zero bytes, an empty block's header repeated, and a comment
/// of [commentLength] bytes added to every central-directory record.
Uint8List _withRecordTrailers(
  Uint8List zip, {
  required int extraLength,
  required int commentLength,
}) {
  final int end = zip.length - _endOfCentralDirectoryLength;
  final ByteData original = ByteData.sublistView(zip, end);
  final int entryCount = original.getUint16(10, Endian.little);
  final int directoryOffset = original.getUint32(16, Endian.little);
  final BytesBuilder directory = BytesBuilder();
  final ByteData data = ByteData.sublistView(zip);
  for (int record = directoryOffset, i = 0; i < entryCount; i++) {
    final int nameEnd = record +
        _centralFileHeaderLength +
        data.getUint16(record + 28, Endian.little);
    final Uint8List head = zip.sublist(record, nameEnd);
    ByteData.sublistView(head)
      ..setUint16(30, extraLength, Endian.little)
      ..setUint16(32, commentLength, Endian.little);
    directory
      ..add(head)
      ..add(Uint8List(extraLength))
      ..add(List<int>.filled(commentLength, 0x4E));
    record = nameEnd;
  }
  final Uint8List records = directory.takeBytes();
  return Uint8List.fromList(<int>[
    ...zip.sublist(0, directoryOffset),
    ...records,
    ..._endOfCentralDirectory(
      entryCount: entryCount,
      centralDirectoryLength: records.length,
      centralDirectoryOffset: directoryOffset,
    ),
  ]);
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
/// to the archive and referenced by nothing. [listed] entries, each named
/// under `OEBPS/`, are added to the archive and to the manifest, so reading
/// the book whole reads them.
Uint8List _craftBook({
  required _CraftedZipEntry chapter,
  List<_CraftedZipEntry> extra = const <_CraftedZipEntry>[],
  List<_CraftedZipEntry> listed = const <_CraftedZipEntry>[],
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
            '${listed.map((_CraftedZipEntry entry) => '<item '
                'id="${entry.name.substring(6).replaceAll('.', '-')}" '
                'href="${entry.name.substring(6)}" '
                'media-type="application/octet-stream"/>').join()}'
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
    ...listed,
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

  group('no limit on the file', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('nge_seed_limits_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    final Uint8List book = _craftBook(
        chapter:
            _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)));

    // TC-LIM-57 [Scenario]: the package sets no limit on a file's size. A
    // book of 600 MiB, its entries after a gap of zeros none of them holds,
    // opens from its bytes, and its entries read within the limits passed.
    test(
        'TC-LIM-57 [Scenario]: bytes past 512 MiB open, and their entries '
        'read within the limits', () async {
      final Uint8List bytes = _afterGap(book, _largeFileLength);
      expect(bytes.length, greaterThan(_largeFileLength));

      final EpubBookRef bookRef =
          await reader.openBook(bytes, maxEntryBytes: _maxEntryBytes);
      expect(bookRef.title, 'NGE-SEED Limits Book');
      expect(
          (await reader.readBook(bytes,
                  maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes))
              .chapters
              .single
              .htmlContent,
          _chapterXhtml);
    });

    // TC-LIM-58 [Scenario]: the same from a file. The file is sparse: it is
    // made its full size by truncating it longer, and only the book, at its
    // end, is written, so its size is real to every read while the disk
    // holds almost nothing.
    test(
        'TC-LIM-58 [Scenario]: a file past 512 MiB opens, and its entries '
        'read within the limits', () async {
      final String path = '${tempDir.path}/sparse.epub';
      File(path).openSync(mode: FileMode.write)
        ..truncateSync(_largeFileLength)
        ..setPositionSync(_largeFileLength)
        ..writeFromSync(_movedTo(book, _largeFileLength))
        ..closeSync();
      expect(File(path).lengthSync(), greaterThan(_largeFileLength));

      final EpubBookRef bookRef =
          await reader.openBookFile(path, maxEntryBytes: _maxEntryBytes);
      expect(await (await bookRef.getChapters()).single.readHtmlContent(),
          _chapterXhtml);
      expect(
          (await reader.readBookFile(path,
                  maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes))
              .chapters
              .single
              .htmlContent,
          _chapterXhtml);
    });

    // TC-LIM-5 [Scenario]: a conventional book opens the same through either
    // kind of entry point, both eagerly and by reference.
    test(
        'TC-LIM-5 [Scenario]: a book read from its file equals the same book '
        'read from its bytes', () async {
      final Uint8List bytes = _buildConventionalBook();
      final String path = '${tempDir.path}/book.epub';
      File(path).writeAsBytesSync(bytes);

      final EpubBook fromFile = await reader.readBookFile(path,
          maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes);
      expect(
          fromFile,
          await reader.readBook(bytes,
              maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes));
      expect(fromFile.title, 'NGE-SEED Path Book');
      expect(
          fromFile.chapters.single.htmlContent, seedXhtml('NGE-SEED-PATH-CH1'));
      expect(fromFile.coverImage, isNotNull);
      expect(await reader.openBookFile(path, maxEntryBytes: _maxEntryBytes),
          await reader.openBook(bytes, maxEntryBytes: _maxEntryBytes));
    });
  });

  group('the central directory, however many entries', () {
    /// A readable book with [count] more entries, each `NGE-SEED-<i>.txt`
    /// holding `NGE-SEED-<i>`.
    Uint8List bookWith(int count) => _craftBook(
          chapter:
              _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
          extra: <_CraftedZipEntry>[
            for (int i = 0; i < count; i++)
              _CraftedZipEntry.stored(
                  'NGE-SEED-$i.txt', utf8.encode('NGE-SEED-$i')),
          ],
        );

    /// The entries the book `_craftBook` writes keeps when it is opened.
    const Set<String> ownEntries = <String>{
      'mimetype',
      'META-INF/container.xml',
      'OEBPS/content.opf',
      'OEBPS/toc.ncx',
      _chapterPath,
    };

    /// The last of the 50 entries `bookWith(50)` adds, read from [zip] once
    /// it is open: found only by a pass over the directory that reads every
    /// record before it.
    Future<List<int>?> lastOf(List<int> zip) async =>
        (await reader.openBook(zip, maxEntryBytes: _maxEntryBytes))
            .readEntry('NGE-SEED-49.txt');

    Future<List<int>?> read(EpubBookRef bookRef, String name) =>
        bookRef.readEntry(name);

    // TC-LIM-59 [Scenario]: the package sets no limit on the number of
    // entries. A book of 10,000 more than its own opens keeping only its
    // own, and an entry deep in the directory reads.
    test(
        'TC-LIM-59 [Scenario]: a book of 10,000 entries opens, and an entry '
        'of them reads', () async {
      final EpubBookRef bookRef = await reader.openBook(bookWith(_manyEntries),
          maxEntryBytes: _maxEntryBytes);

      expect(bookRef.knownEntrySizes.keys, unorderedEquals(ownEntries));
      expect(await read(bookRef, 'NGE-SEED-7777.txt'),
          utf8.encode('NGE-SEED-7777'));
    });

    // TC-LIM-25 [Error guessing]: the entries are taken from the central
    // directory's records, whatever count the end record claims: here one.
    test(
        'TC-LIM-25 [Error guessing]: every record is read, whatever count the '
        'end record claims', () async {
      final Uint8List zip = bookWith(50);
      ByteData.sublistView(zip)
        ..setUint16(
            zip.length - _endOfCentralDirectoryLength + 8, 1, Endian.little)
        ..setUint16(
            zip.length - _endOfCentralDirectoryLength + 10, 1, Endian.little);

      expect(await lastOf(zip), utf8.encode('NGE-SEED-49'));
    });

    // TC-LIM-26 [Equivalence partitioning]: a zip64 end record moves the
    // central directory's place into the zip64 record, and the reading
    // follows it there.
    test('TC-LIM-26 [EP]: behind a zip64 end record, every record is read',
        () async {
      expect(await lastOf(_withZip64EndRecord(bookWith(50))),
          utf8.encode('NGE-SEED-49'));
    });

    // TC-LIM-27 [Error guessing]: an end record marked zip64 with no zip64
    // record behind it keeps its own values, as `package:archive` does, and
    // the reading still walks the real directory.
    test(
        'TC-LIM-27 [Error guessing]: a zip64 marker with no zip64 record '
        'still has every record read', () async {
      final Uint8List zip = bookWith(50);
      ByteData.sublistView(zip).setUint16(
          zip.length - _endOfCentralDirectoryLength + 8, 0xFFFF, Endian.little);

      expect(await lastOf(zip), utf8.encode('NGE-SEED-49'));
    });

    // TC-LIM-28 [Error guessing]: bytes with no end record have no directory
    // to read, and are not a ZIP at all. Zeros are the case that matters:
    // read as an end record anyway, they describe an empty directory at
    // offset 0, and the file would open as a ZIP with no entries.
    test(
        'TC-LIM-28 [Error guessing]: bytes that are not a ZIP fail as a '
        'corrupt archive', () {
      expect(
          reader.openBook(Uint8List(64)..fillRange(0, 64, 0xAB),
              maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
      expect(reader.openBook(Uint8List(64), maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
    });

    // TC-LIM-29 [Error guessing]: a record's extra field and comment are part
    // of its length. Stepping over them wrongly would lose the next
    // record's signature and stop the reading at one.
    test(
        'TC-LIM-29 [Error guessing]: records with extra fields and comments '
        'are each read', () async {
      final EpubBookRef bookRef = await reader.openBook(
          _withRecordTrailers(bookWith(50), extraLength: 4, commentLength: 3),
          maxEntryBytes: _maxEntryBytes);

      expect(bookRef.knownEntrySizes.keys, unorderedEquals(ownEntries));
      expect(
          await read(bookRef, 'NGE-SEED-49.txt'), utf8.encode('NGE-SEED-49'));
    });

    // TC-LIM-30 [Error guessing]: an end record at the very first byte, with
    // the entries and their directory after it. `package:archive` finds it
    // all the same, so the reading has to as well.
    test(
        'TC-LIM-30 [Error guessing]: records behind an end record at offset '
        '0 are each read', () async {
      final _ZipBody(
        :Uint8List body,
        :int directoryOffset,
        :int directoryLength,
        :int entryCount
      ) = _bodyAt(bookWith(50), _endOfCentralDirectoryLength);

      expect(
          await lastOf(<int>[
            ..._endOfCentralDirectory(
              entryCount: entryCount,
              centralDirectoryLength: directoryLength,
              centralDirectoryOffset: directoryOffset,
            ),
            ...body,
          ]),
          utf8.encode('NGE-SEED-49'));
    });

    // TC-LIM-66 [Boundary]: a central directory at the very first byte, the
    // entries after it and the end record last. A structure starting where
    // its file does is inside it, so the directory is read from offset 0.
    test(
        'TC-LIM-66 [Boundary]: a central directory at offset 0 has every '
        'record read', () async {
      final Uint8List zip = bookWith(50);
      final int directoryLength = _bodyAt(zip, 0).directoryLength;
      final _ZipBody moved = _bodyAt(zip, directoryLength);
      final int localsLength = moved.directoryOffset - directoryLength;

      expect(
          await lastOf(<int>[
            ...moved.body.sublist(localsLength),
            ...moved.body.sublist(0, localsLength),
            ..._endOfCentralDirectory(
              entryCount: moved.entryCount,
              centralDirectoryLength: directoryLength,
              centralDirectoryOffset: 0,
            ),
          ]),
          utf8.encode('NGE-SEED-49'));
    });

    // TC-LIM-31 [Error guessing]: a zip64 locator at the very first byte,
    // then the end record, the zip64 record, and the entries. The locator
    // counts even there.
    test(
        'TC-LIM-31 [Error guessing]: records behind a zip64 locator at '
        'offset 0 are each read', () async {
      const int zip64Record = 20 + _endOfCentralDirectoryLength;
      const int headLength = zip64Record + 56;
      final _ZipBody(
        :Uint8List body,
        :int directoryOffset,
        :int directoryLength,
        :int entryCount
      ) = _bodyAt(bookWith(50), headLength);
      final ByteData head = ByteData(headLength)
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
        ..setUint64(zip64Record + 24, entryCount, Endian.little)
        ..setUint64(zip64Record + 32, entryCount, Endian.little)
        ..setUint64(zip64Record + 40, directoryLength, Endian.little)
        ..setUint64(zip64Record + 48, directoryOffset, Endian.little);

      expect(await lastOf(<int>[...head.buffer.asUint8List(), ...body]),
          utf8.encode('NGE-SEED-49'));
    });

    // TC-LIM-41 [Boundary]: a zip64 record at the very first byte, then the
    // entries, the locator pointing at offset 0, and the end record. Offset
    // 0 is in the file, so the record is read there.
    test(
        'TC-LIM-41 [Boundary]: records behind a zip64 record at offset 0 are '
        'each read', () async {
      const int zip64RecordLength = 56;
      final _ZipBody(
        :Uint8List body,
        :int directoryOffset,
        :int directoryLength,
        :int entryCount
      ) = _bodyAt(bookWith(50), zip64RecordLength);
      final ByteData zip64Record = ByteData(zip64RecordLength)
        ..setUint32(0, 0x06064b50, Endian.little)
        ..setUint64(4, zip64RecordLength - 12, Endian.little)
        ..setUint64(24, entryCount, Endian.little)
        ..setUint64(32, entryCount, Endian.little)
        ..setUint64(40, directoryLength, Endian.little)
        ..setUint64(48, directoryOffset, Endian.little);
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
          await lastOf(<int>[
            ...zip64Record.buffer.asUint8List(),
            ...body,
            ...tail.buffer.asUint8List(),
          ]),
          utf8.encode('NGE-SEED-49'));
    });

    // TC-LIM-32 [Equivalence partitioning]: any one of the end record's four
    // fields at its maximum sends a reader to the zip64 record. Here the end
    // record's own fields describe an empty directory, and only the zip64
    // record points at the real one.
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
          'zip64 has the zip64 record read', () async {
        expect(await lastOf(marker.value(bookWith(50))),
            utf8.encode('NGE-SEED-49'));
      });
    }
  });

  group('inflated sizes, counted when an entry is read', () {
    /// A readable book with [extra] entries nothing in it points at.
    Future<EpubBookRef> openWith(List<_CraftedZipEntry> extra) =>
        reader.openBook(
            _craftBook(
              chapter: _CraftedZipEntry.stored(
                  _chapterPath, utf8.encode(_chapterXhtml)),
              extra: extra,
            ),
            maxEntryBytes: _maxEntryBytes);

    Future<List<int>?> read(EpubBookRef bookRef, String name) =>
        bookRef.readEntry(name);

    /// A readable book whose manifest also lists [listed], which reading it
    /// whole reads with the rest.
    Uint8List bookListing(List<_CraftedZipEntry> listed) => _craftBook(
          chapter:
              _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
          listed: listed,
        );

    /// What is left of the whole-archive limit once a book listing
    /// `half.bin`, `rest.bin` and `one.bin` has had its own documents and one
    /// entry at the per-entry limit read whole: reading a book whole reads
    /// the documents opening parses and the chapter, which count like any
    /// other entry. They are the same in every book listing those names.
    late final int restLength;
    late final Uint8List restDeflated;

    setUpAll(() async {
      final EpubBookRef opened = await reader.openBook(
          bookListing(<_CraftedZipEntry>[
            for (final String name in <String>['half', 'rest', 'one'])
              _CraftedZipEntry.stored('OEBPS/$name.bin', const <int>[]),
          ]),
          maxEntryBytes: _maxEntryBytes);
      final List<String> names = <String>[
        'META-INF/container.xml',
        'OEBPS/content.opf',
        'OEBPS/toc.ncx',
        _chapterPath,
      ];
      int readWhole = 0;
      for (final String name in names) {
        readWhole += (await read(opened, name))!.length;
      }
      restLength = _maxTotalBytes - _maxEntryBytes - readWhole;
      restDeflated = _rawDeflateOf(restLength);
    });

    /// A book listing entries that, read whole with the book's own
    /// documents, inflate to exactly the whole-archive limit, or with
    /// [oneMore] one byte more.
    Uint8List filledToTheLimit({required bool oneMore}) =>
        bookListing(<_CraftedZipEntry>[
          _deflateEntry('OEBPS/half.bin', _deflateToEntryLimit,
              declaredUncompressedSize: _maxEntryBytes),
          _deflateEntry('OEBPS/rest.bin', restDeflated,
              declaredUncompressedSize: restLength),
          _CraftedZipEntry.stored(
              'OEBPS/one.bin', oneMore ? const <int>[0x4E] : const <int>[]),
        ]);

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

      final EpubBookRef bookRef =
          await reader.openBook(book, maxEntryBytes: _maxEntryBytes);
      expect(
          (await reader.readBook(book,
                  maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes))
              .chapters
              .single
              .htmlContent,
          _chapterXhtml);
      await expectLater(read(bookRef, 'OEBPS/film.bin'), _throwsTooLarge);
    });

    // TC-LIM-60 [Scenario]: with no limit passed, nothing stops an entry. The
    // same 300 MiB entry, a quarter of a MiB deflated, reads whole, through
    // a ref and through a book read whole that lists it.
    test('TC-LIM-60 [Scenario]: with no limit, an entry of 300 MiB reads whole',
        () async {
      final Uint8List film = _rawDeflateOf(300 * _oneMib);
      final EpubBookRef bookRef = await reader.openBook(
          _craftBook(
            chapter: _CraftedZipEntry.stored(
                _chapterPath, utf8.encode(_chapterXhtml)),
            extra: <_CraftedZipEntry>[
              _deflateEntry('OEBPS/film.bin', film,
                  declaredUncompressedSize: 1024),
            ],
          ),
          maxEntryBytes: null);
      expect(await read(bookRef, 'OEBPS/film.bin'), hasLength(300 * _oneMib));

      final EpubBook book = await reader.readBook(
          bookListing(<_CraftedZipEntry>[
            _deflateEntry('OEBPS/film.bin', film,
                declaredUncompressedSize: 1024),
          ]),
          maxEntryBytes: null,
          maxTotalBytes: null);
      expect(
          (book.content.allFiles['film.bin']! as EpubByteContentFile).content,
          hasLength(300 * _oneMib));
    });

    // TC-LIM-9 [Boundary]: a declared size is only how large a buffer to
    // inflate into: no larger than the limit, nor than the entry's own bytes
    // can inflate to, stored or deflated. An entry declaring 1 TiB through
    // zip64 and holding one byte opens, and reads as that byte, under a
    // limit, a limit as large as the size it declares, or none; a buffer of
    // the size it declares could not be allocated.
    final Map<String, _CraftedZipEntry> oneByteEntries =
        <String, _CraftedZipEntry>{
      'stored': const _CraftedZipEntry(
        name: 'OEBPS/big.bin',
        method: _storeMethod,
        declaredUncompressedSize: 0,
        payload: <int>[0x4E],
        zip64UncompressedSize: 1 << 40,
      ),
      'deflated': _CraftedZipEntry(
        name: 'OEBPS/big.bin',
        method: _deflateMethod,
        declaredUncompressedSize: 0,
        payload: _rawDeflateOf(1, block: Uint8List.fromList(<int>[0x4E])),
        zip64UncompressedSize: 1 << 40,
      ),
    };
    for (final MapEntry<String, _CraftedZipEntry> entry
        in oneByteEntries.entries) {
      for (final int? limit in <int?>[_maxEntryBytes, 1 << 40, null]) {
        test(
            'TC-LIM-9 [Boundary]: a ${entry.key} entry declaring 1 TiB that '
            'holds one byte reads as that byte, the limit $limit', () async {
          final EpubBookRef bookRef = await reader.openBook(
              _craftBook(
                chapter: _CraftedZipEntry.stored(
                    _chapterPath, utf8.encode(_chapterXhtml)),
                listed: <_CraftedZipEntry>[entry.value],
              ),
              maxEntryBytes: limit);

          expect(bookRef.knownEntrySizes['OEBPS/big.bin'], 1 << 40);
          expect(await read(bookRef, 'OEBPS/big.bin'), <int>[0x4E]);
        });
      }
    }

    // TC-LIM-67 [Boundary]: the limit caps the buffer as well as the read.
    // An entry declaring 1 TiB whose 64 MiB of deflated bytes could inflate
    // to 66 GiB is read under a 256 MiB limit into a buffer of that limit,
    // and refused when it passes it; a buffer of what the bytes could
    // produce could not be allocated.
    test(
        'TC-LIM-67 [Boundary]: an entry declaring and able to produce far more '
        'than the limit is refused at the limit', () async {
      final EpubBookRef bookRef = await reader.openBook(
          _craftBook(
            chapter: _CraftedZipEntry.stored(
                _chapterPath, utf8.encode(_chapterXhtml)),
            extra: <_CraftedZipEntry>[
              _CraftedZipEntry(
                name: 'big.bin',
                method: _deflateMethod,
                declaredUncompressedSize: 0,
                payload: _deflateOneOverEntryLimit,
                zeroRunLength: 64 * _oneMib,
                zip64UncompressedSize: 1 << 40,
              ),
            ],
          ),
          maxEntryBytes: _maxEntryBytes);

      await expectLater(read(bookRef, 'big.bin'), _throwsTooLarge);
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
        expect(await read(bookRef, 'part$i.bin'), isEmpty);
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

      await expectLater(read(bookRef, 'liar.bin'), _throwsTooLarge);
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

      expect(await read(bookRef, 'atlimit.bin'), hasLength(_maxEntryBytes));
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

      final EpubBookRef bookRef =
          await reader.openBook(book, maxEntryBytes: _maxEntryBytes);
      await expectLater(read(bookRef, _chapterPath), _throwsTooLarge);
      expect(
          reader.readBook(book,
              maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes),
          _throwsTooLarge);
    });

    // TC-LIM-15 [Boundary]: an `EpubBookRef` holds each read to the
    // per-entry limit alone. Reads of one ref inflating to 912 MiB between
    // them, past the whole-archive limit, none past the per-entry limit, are
    // each read, the first entry a second time after the others.
    test(
        'TC-LIM-15 [Boundary]: reads of one ref inflating to 912 MiB between '
        'them are each read', () async {
      final EpubBookRef bookRef = await openWith(<_CraftedZipEntry>[
        _deflateEntry('a.bin', _deflateToEntryLimit,
            declaredUncompressedSize: _maxEntryBytes),
        _deflateEntry('b.bin', _deflateTo200Mib,
            declaredUncompressedSize: 200 * _oneMib),
        _deflateEntry('c.bin', _deflateTo200Mib,
            declaredUncompressedSize: 1024),
      ]);

      expect(await read(bookRef, 'a.bin'), hasLength(_maxEntryBytes));
      expect(await read(bookRef, 'b.bin'), hasLength(200 * _oneMib));
      expect(await read(bookRef, 'c.bin'), hasLength(200 * _oneMib));
      expect(await read(bookRef, 'a.bin'), hasLength(_maxEntryBytes));
    });

    // TC-LIM-16 [Boundary]: reading a book whole, whose entries inflate to
    // exactly the whole-archive limit, the documents opening parsed
    // included, is admissible. The chapter and the NCX are each read twice
    // in the one call, and inflated and counted once: counting either again
    // would push the book past the limit.
    test(
        'TC-LIM-16 [Boundary]: a book read whole inflating to exactly the '
        'total limit is read, an entry read twice counted once', () async {
      final EpubBook book = await reader.readBook(
          filledToTheLimit(oneMore: false),
          maxEntryBytes: _maxEntryBytes,
          maxTotalBytes: _maxTotalBytes);

      List<int> contentOf(String name) =>
          (book.content.allFiles[name]! as EpubByteContentFile).content;
      expect(contentOf('half.bin'), hasLength(_maxEntryBytes));
      expect(contentOf('rest.bin'), hasLength(restLength));
      expect(book.chapters.single.htmlContent, _chapterXhtml);
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

      await expectLater(read(bookRef, 'liar.bin'), _throwsTooLarge);
    });

    // TC-LIM-18 [Boundary]: reading a book whole one byte past the
    // whole-archive limit is refused, from its bytes and from its file. The
    // limit is the one call's: the same book opened as a ref reads every
    // entry.
    test(
        'TC-LIM-18 [Boundary]: a book read whole inflating one byte past the '
        'total limit is refused; as a ref, each entry reads', () async {
      final Uint8List book = filledToTheLimit(oneMore: true);
      final Directory scratch =
          Directory.systemTemp.createTempSync('nge_seed_total_');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final String path = '${scratch.path}/book.epub';
      File(path).writeAsBytesSync(book);

      await expectLater(
          reader.readBook(book,
              maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes),
          _throwsTooLarge);
      await expectLater(
          reader.readBookFile(path,
              maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes),
          _throwsTooLarge);

      final EpubBookRef bookRef =
          await reader.openBook(book, maxEntryBytes: _maxEntryBytes);
      expect(await read(bookRef, 'OEBPS/half.bin'), hasLength(_maxEntryBytes));
      expect(await read(bookRef, 'OEBPS/rest.bin'), hasLength(restLength));
      expect(await read(bookRef, 'OEBPS/one.bin'), <int>[0x4E]);
    });

    // TC-LIM-65 [Scenario]: with no limits passed, a book read whole is not
    // stopped however much its entries inflate to between them: the book
    // TC-LIM-18 refuses, one byte past 512 MiB, reads.
    test(
        'TC-LIM-65 [Scenario]: with no limits, a book read whole past 512 MiB '
        'reads', () async {
      final EpubBook book = await reader.readBook(
          filledToTheLimit(oneMore: true),
          maxEntryBytes: null,
          maxTotalBytes: null);

      List<int> contentOf(String name) =>
          (book.content.allFiles[name]! as EpubByteContentFile).content;
      expect(contentOf('half.bin'), hasLength(_maxEntryBytes));
      expect(contentOf('rest.bin'), hasLength(restLength));
      expect(contentOf('one.bin'), <int>[0x4E]);
    });

    // TC-LIM-55 [Boundary]: reading a book whole holds each entry to the
    // per-entry limit as well: one entry inflating one byte past it is
    // refused, although the book's entries between them stay inside the
    // whole-archive limit.
    test(
        'TC-LIM-55 [Boundary]: a book read whole with an entry one byte past '
        'the per-entry limit is refused', () async {
      expect(
          reader.readBook(
              bookListing(<_CraftedZipEntry>[
                _deflateEntry('OEBPS/over.bin', _deflateOneOverEntryLimit,
                    declaredUncompressedSize: _maxEntryBytes + 1),
              ]),
              maxEntryBytes: _maxEntryBytes,
              maxTotalBytes: _maxTotalBytes),
          _throwsTooLarge);
    });
  });

  group('limits the caller passes', () {
    const int limit = 2 * 1024;

    /// A readable book whose chapter and cover each hold [length] bytes or
    /// more: the chapter padded with text, the cover with bytes after the
    /// image's end, which decoders ignore. `OEBPS/unlisted.bin`, which its
    /// manifest leaves out, holds one byte more. Its own documents stay
    /// under [limit].
    Uint8List bookOf(int length) => buildEpubArchive(
          opfPath: 'OEBPS/content.opf',
          textEntries: <String, String>{
            'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
                '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
                'unique-identifier="uid">'
                '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
                '<dc:identifier id="uid">urn:uuid:NGE-SEED-CALLER'
                '</dc:identifier>'
                '<dc:title>NGE-SEED Caller Book</dc:title>'
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
                '<head/><docTitle><text>NGE-SEED Caller Book</text></docTitle>'
                '<navMap><navPoint id="np-1" playOrder="1">'
                '<navLabel><text>NGE-SEED Chapter</text></navLabel>'
                '<content src="chapter1.xhtml"/>'
                '</navPoint></navMap>'
                '</ncx>',
            _chapterPath: seedXhtml('NGE-SEED-${'N' * length}'),
          },
          binaryEntries: <String, List<int>>{
            'OEBPS/cover.png': <int>[...seedPngBytes(), ...Uint8List(length)],
            'OEBPS/unlisted.bin': Uint8List(length + 1),
          },
        );

    /// Every read an [EpubBookRef] makes of its chapter and its cover, and
    /// of an entry its manifest leaves out.
    Map<String, Future<Object?> Function(EpubBookRef)> readsOf() =>
        <String, Future<Object?> Function(EpubBookRef)>{
          'readContentAsText': (EpubBookRef bookRef) =>
              bookRef.content.html['chapter1.xhtml']!.readContentAsText(),
          'readContentAsBytes': (EpubBookRef bookRef) =>
              bookRef.content.html['chapter1.xhtml']!.readContentAsBytes(),
          'getContentStream': (EpubBookRef bookRef) async =>
              bookRef.content.html['chapter1.xhtml']!.getContentStream(),
          'openContentStream': (EpubBookRef bookRef) async {
            final EpubTextContentFileRef chapter =
                bookRef.content.html['chapter1.xhtml']!;
            return chapter.openContentStream(chapter.getContentFileEntry());
          },
          'readHtmlContent': (EpubBookRef bookRef) async =>
              (await bookRef.getChapters()).single.readHtmlContent(),
          'readCover': (EpubBookRef bookRef) => bookRef.readCover(),
          'readCoverBytes': (EpubBookRef bookRef) => bookRef.readCoverBytes(),
          'ArchiveFile.content': (EpubBookRef bookRef) async => bookRef
              .content.html['chapter1.xhtml']!
              .getContentFileEntry()
              .content,
          'ArchiveFile.writeContent': (EpubBookRef bookRef) async {
            final OutputStream output = OutputStream();
            bookRef.content.html['chapter1.xhtml']!
                .getContentFileEntry()
                .writeContent(output);
            return output.getBytes();
          },
          'readEntry': (EpubBookRef bookRef) => bookRef.readEntry(_chapterPath),
          'readEntry of an entry the manifest leaves out':
              (EpubBookRef bookRef) => bookRef.readEntry('OEBPS/unlisted.bin'),
        };

    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('nge_seed_caller_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    /// The book [bytes] opened from its bytes and from a file, each entry
    /// held to [maxEntryBytes].
    Future<List<EpubBookRef>> openedBothWays(
        Uint8List bytes, int? maxEntryBytes) async {
      final String path = '${tempDir.path}/book.epub';
      File(path).writeAsBytesSync(bytes);
      return <EpubBookRef>[
        await reader.openBook(bytes, maxEntryBytes: maxEntryBytes),
        await reader.openBookFile(path, maxEntryBytes: maxEntryBytes),
      ];
    }

    // TC-LIM-61 [Equivalence partitioning]: `maxEntryBytes` holds every read
    // an opened book makes of an entry, from bytes and from a file alike.
    // The chapter and the cover each hold more than the limit, the book's
    // own documents less, so the book opens and every read of either is
    // refused; held to twice the size instead, each reads.
    for (final MapEntry<String, Future<Object?> Function(EpubBookRef)> read
        in readsOf().entries) {
      test(
          'TC-LIM-61 [EP]: ${read.key} is held to the maxEntryBytes the book '
          'was opened with', () async {
        for (final EpubBookRef bookRef
            in await openedBothWays(bookOf(limit), limit)) {
          await expectLater(read.value(bookRef), _throwsTooLarge);
        }
        for (final EpubBookRef bookRef
            in await openedBothWays(bookOf(limit), 4 * limit)) {
          expect(await read.value(bookRef), isNotNull);
        }
      });
    }

    // TC-LIM-62 [Boundary]: a limit of 0 is a limit, not an argument error:
    // the documents opening parses already pass it.
    test('TC-LIM-62 [Boundary]: a limit of 0 refuses every entry with bytes',
        () async {
      await expectLater(
          reader.openBook(bookOf(0), maxEntryBytes: 0), _throwsTooLarge);
      await expectLater(
          reader.readBook(bookOf(0), maxEntryBytes: null, maxTotalBytes: 0),
          _throwsTooLarge);
    });

    // TC-LIM-63 [Equivalence partitioning]: a limit below zero is the
    // caller's mistake, not the book's: an `ArgumentError`, from every entry
    // point, for either limit.
    test('TC-LIM-63 [EP]: a limit below zero is an argument error', () async {
      final Uint8List bytes = bookOf(0);
      final String path = '${tempDir.path}/book.epub';
      File(path).writeAsBytesSync(bytes);

      await expectLater(
          reader.openBook(bytes, maxEntryBytes: -1), throwsArgumentError);
      await expectLater(
          reader.openBookFile(path, maxEntryBytes: -1), throwsArgumentError);
      for (final _Limits limits in const <_Limits>[
        _Limits(-1, null),
        _Limits(null, -1),
      ]) {
        await expectLater(
            reader.readBook(bytes,
                maxEntryBytes: limits.entry, maxTotalBytes: limits.total),
            throwsArgumentError);
        await expectLater(
            reader.readBookFile(path,
                maxEntryBytes: limits.entry, maxTotalBytes: limits.total),
            throwsArgumentError);
      }
    });

    // TC-LIM-64 [Equivalence partitioning]: `readBook` holds its entries to
    // whichever limits it is given. Its chapter and cover hold 2 KiB each:
    // 2 KiB for one entry, or 4 KiB between them all, is too little, each
    // alone, with the other left out; 8 KiB for one and 16 KiB for all, or
    // no limit at all, is enough.
    test(
        'TC-LIM-64 [EP]: readBook holds its entries to either limit alone, '
        'and to neither when both are null', () async {
      final Uint8List bytes = bookOf(limit);

      await expectLater(
          reader.readBook(bytes, maxEntryBytes: limit, maxTotalBytes: null),
          _throwsTooLarge);
      await expectLater(
          reader.readBook(bytes, maxEntryBytes: null, maxTotalBytes: 2 * limit),
          _throwsTooLarge);
      for (final _Limits limits in const <_Limits>[
        _Limits(4 * limit, 8 * limit),
        _Limits(4 * limit, null),
        _Limits(null, 8 * limit),
        _Limits(null, null),
      ]) {
        final EpubBook book = await reader.readBook(bytes,
            maxEntryBytes: limits.entry, maxTotalBytes: limits.total);
        expect(book.coverImage, isNotNull);
      }
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

        expect(
            reader.openBook(Uint8List.sublistView(zip, 0, zip.length - cut),
                maxEntryBytes: _maxEntryBytes),
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
            reader.openBook(Uint8List.fromList(<int>[...zip, ...comment.value]),
                maxEntryBytes: _maxEntryBytes),
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
              patched((int length, int offset) => 46 + 12, offsetShift: 1000),
              maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
      expect(
          reader.openBook(patched((int length, int offset) => length - offset),
              maxEntryBytes: _maxEntryBytes),
          _throwsDecodedWithoutContainer);
      expect(
          reader.openBook(
              patched((int length, int offset) => length - offset + 1),
              maxEntryBytes: _maxEntryBytes),
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

      expect(
          reader.openBook(zip64With(size: -1), maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
      expect(
          reader.openBook(zip64With(offset: -1), maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
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
          reader.openBook(pointedAt((int length) => length),
              maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
      expect(
          reader.openBook(pointedAt((int length) => -1),
              maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
      expect(
          reader.openBook(pointedAt((int length) => length - 55, signed: true),
              maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
      expect(
          reader.openBook(pointedAt((int length) => length - 56),
              maxEntryBytes: _maxEntryBytes),
          _throwsDecodedWithoutContainer);
    });

    // TC-LIM-40 [Error guessing]: a central directory that ends in a few
    // stray bytes, too few for another record's signature, is read to its
    // last whole record and no further.
    test(
        'TC-LIM-40 [Error guessing]: stray bytes after the last directory '
        'record are ignored', () {
      expect(
          reader.openBook(
              _withDirectoryTail(
                  _craftZip(oneEntry()), const <int>[0x4E, 0x47, 0x45]),
              maxEntryBytes: _maxEntryBytes),
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
            reader.openBook(
                _withDirectoryTail(_craftZip(oneEntry()), <int>[
                  ...signature.buffer.asUint8List(),
                  ...List<int>.filled(tail.key, 0),
                ]),
                maxEntryBytes: _maxEntryBytes),
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

    /// A read of the entry [name] of [book], opened and not yet read.
    Future<Future<Uint8List?> Function()> opened(
        Uint8List book, String name) async {
      final EpubBookRef bookRef =
          await reader.openBook(book, maxEntryBytes: _maxEntryBytes);
      return () => bookRef.readEntry(name);
    }

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

      final Future<Uint8List?> Function() stray = await opened(book, strayPath);
      expect(
          (await reader.readBook(book,
                  maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes))
              .chapters
              .single
              .htmlContent,
          _chapterXhtml);
      await expectLater(stray(), _throwsCorrupt);
    });

    // TC-LIM-43 [Boundary]: the local header a record points at has to fit
    // in the file, its fixed 30 bytes at least. Negative, or with its
    // signature there but one byte short, fails the entry's read; the last
    // place it fits is read. The book opens either way.
    test(
        'TC-LIM-43 [Boundary]: a local header placed where it does not fit '
        'fails its entry when it is read', () async {
      final Future<Uint8List?> Function() negative = await opened(
          bookWith(const _CraftedZipEntry(
            name: extraPath,
            method: _storeMethod,
            declaredUncompressedSize: 0,
            zip64LocalHeaderOffset: -1,
          )),
          extraPath);
      await expectLater(negative(), _throwsCorrupt);

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

      expect(await (await opened(localHeaderAtEnd(0), extraPath))(), isEmpty);
      final Future<Uint8List?> Function() cut =
          await opened(localHeaderAtEnd(1), extraPath);
      await expectLater(cut(), _throwsCorrupt);
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

        final Future<Uint8List?> Function() extra =
            await opened(book, extraPath);
        await expectLater(extra(), _throwsCorrupt);
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
      final Uint8List zip = _sharedLocalHeaderZip(4096);
      ByteData.sublistView(zip).setUint32(0, 0, Endian.little);

      expect(reader.openBook(zip, maxEntryBytes: _maxEntryBytes),
          _throwsDecodedWithoutContainer);
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
          reader.openBook(
              _sharedStreamZip(
                method: _deflateMethod,
                payload: stream,
                compressedSizes: List<int>.filled(4096, stream.length),
              ),
              maxEntryBytes: _maxEntryBytes),
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

      expect(reader.openBook(zip(dataStart), maxEntryBytes: _maxEntryBytes),
          _throwsDecodedWithoutContainer);
      expect(reader.openBook(zip(dataStart + 1), maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
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
            reader.openBook(
                _sharedStreamZip(
                  method: _deflateMethod,
                  payload: stream,
                  compressedSizes: List<int>.filled(4096, 0),
                  zip64CompressedSize: size.value,
                ),
                maxEntryBytes: _maxEntryBytes),
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
        expect(reader.openBook(size.value(0), maxEntryBytes: _maxEntryBytes),
            _throwsDecodedWithoutContainer);
        expect(reader.openBook(size.value(-1), maxEntryBytes: _maxEntryBytes),
            _throwsCorrupt);
      });
    }
  });

  group('records the book does not keep', () {
    const String strayPath = 'NGE-SEED/stray.bin';

    /// A readable book with one entry more, at [strayPath], which nothing
    /// in it points at and opening does not keep.
    Uint8List bookWith(_CraftedZipEntry stray) => _craftBook(
          chapter:
              _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
          extra: <_CraftedZipEntry>[stray],
        );

    /// The compressed sizes [zip]'s records declare, added up.
    int compressedTotal(Uint8List zip) {
      final ByteData data = ByteData.sublistView(zip);
      int total = 0;
      for (int record = data.getUint32(
              zip.length - _endOfCentralDirectoryLength + 16, Endian.little);
          data.getUint32(record, Endian.little) == _centralFileHeaderSignature;
          record += _centralFileHeaderLength +
              data.getUint16(record + 28, Endian.little) +
              data.getUint16(record + 30, Endian.little) +
              data.getUint16(record + 32, Endian.little)) {
        total += data.getUint32(record + 20, Endian.little);
      }
      return total;
    }

    // TC-LIM-68 [Error guessing]: every record is checked as opening reads
    // it, kept or not. One the book does not keep, declaring -1 through
    // zip64, uncompressed or compressed, fails the book as a damaged
    // directory; declaring 0 the same way, it opens.
    final Map<String, void Function(Uint8List zip, int record)> sizeByField =
        <String, void Function(Uint8List zip, int record)>{
      'uncompressed': (Uint8List zip, int record) {},
      // The zip64 field holds whichever size is marked 0xFFFFFFFF: the
      // compressed one, once the uncompressed one is not.
      'compressed': (Uint8List zip, int record) => ByteData.sublistView(zip)
        ..setUint32(record + 20, 0xFFFFFFFF, Endian.little)
        ..setUint32(record + 24, 0, Endian.little),
    };
    for (final MapEntry<String, void Function(Uint8List, int)> field
        in sizeByField.entries) {
      test(
          'TC-LIM-68 [Error guessing]: a record the book does not keep '
          'declaring a ${field.key} size of -1 fails opening', () async {
        Uint8List zip(int size) {
          final Uint8List book = bookWith(_CraftedZipEntry(
            name: strayPath,
            method: _storeMethod,
            declaredUncompressedSize: 0,
            zip64UncompressedSize: size,
          ));
          field.value(book, _recordOf(book, strayPath));
          return book;
        }

        expect(
            (await reader.openBook(zip(0), maxEntryBytes: _maxEntryBytes))
                .knownEntrySizes,
            isNot(contains(strayPath)));
        await expectLater(
            reader.openBook(zip(-1), maxEntryBytes: _maxEntryBytes),
            _throwsCorrupt);
      });

      // TC-LIM-70 [Error guessing]: a record read after the book was
      // opened, found by name, is checked as opening checks every record.
      // Opened with its zip64 size 0, then changed in place to declare -1,
      // it fails as a damaged directory when it is read, with the message
      // opening gives, not as an error outside the package's own.
      test(
          'TC-LIM-70 [Error guessing]: a record changed after opening to '
          'declare a ${field.key} size of -1 fails when it is found', () async {
        final Uint8List book = bookWith(const _CraftedZipEntry(
          name: strayPath,
          method: _storeMethod,
          declaredUncompressedSize: 0,
          zip64UncompressedSize: 0,
        ));
        final int record = _recordOf(book, strayPath);
        field.value(book, record);
        final EpubBookRef bookRef =
            await reader.openBook(book, maxEntryBytes: _maxEntryBytes);
        ByteData.sublistView(book).setInt64(
            record +
                _centralFileHeaderLength +
                utf8.encode(strayPath).length +
                4,
            -1,
            Endian.little);

        await expectLater(
            bookRef.readEntry(strayPath),
            throwsA(isA<EpubCorruptArchiveException>().having(
                (EpubCorruptArchiveException e) => e.message,
                'message',
                startsWith('An entry declares a negative size'))));
      });
    }

    // TC-LIM-69 [Boundary]: a record the book does not keep counts towards
    // the compressed total all the same. Claiming every byte the others
    // leave of the file, it opens; one byte more, the entries overlap and
    // the book fails as a damaged directory.
    test(
        'TC-LIM-69 [Boundary]: a record the book does not keep overlapping '
        'the others fails opening', () async {
      Uint8List zip(int over) {
        final Uint8List book =
            bookWith(_CraftedZipEntry.stored(strayPath, const <int>[0x4E]));
        final int record = _recordOf(book, strayPath);
        final ByteData data = ByteData.sublistView(book);
        final int others =
            compressedTotal(book) - data.getUint32(record + 20, Endian.little);
        data.setUint32(record + 20, book.length - others + over, Endian.little);
        return book;
      }

      expect(
          (await reader.openBook(zip(0), maxEntryBytes: _maxEntryBytes)).title,
          'NGE-SEED Limits Book');
      await expectLater(reader.openBook(zip(1), maxEntryBytes: _maxEntryBytes),
          _throwsCorrupt);
    });
  });

  group('records of one name', () {
    // TC-LIM-71 [Error guessing]: two records of a name the manifest lists,
    // both pointing at one local header, the later declaring fewer bytes.
    // They are two records, so the later is the entry, as the later record
    // of a name always is: it reads as the bytes it declares, and its sizes
    // are the ones `knownEntrySizes` gives.
    test(
        'TC-LIM-71 [Error guessing]: of two records at one local header with '
        'other sizes, the later is read', () async {
      const String name = 'OEBPS/dup.bin';
      final Uint8List book = _craftBook(
        chapter:
            _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
        listed: <_CraftedZipEntry>[
          _CraftedZipEntry.stored(name, utf8.encode('NGE-SEED-FIRST-LONGER')),
          _CraftedZipEntry.stored('OEBPS/dvp.bin', utf8.encode('NGE-SEED-X')),
        ],
      );
      final int first = _recordOf(book, name);
      final int later = _recordOf(book, 'OEBPS/dvp.bin');
      book.setAll(later + _centralFileHeaderLength, utf8.encode(name));
      ByteData.sublistView(book)
        ..setUint32(later + 20, 8, Endian.little)
        ..setUint32(later + 24, 8, Endian.little)
        ..setUint32(
            later + 42,
            ByteData.sublistView(book).getUint32(first + 42, Endian.little),
            Endian.little);
      final EpubBookRef bookRef =
          await reader.openBook(book, maxEntryBytes: _maxEntryBytes);

      expect(bookRef.knownEntrySizes[name], 8);
      expect(await bookRef.readEntry(name), utf8.encode('NGE-SEED'));
    });

    // TC-LIM-72 [Error guessing]: opening reads the caller's bytes again for
    // each pass, and they can change in between. Each case changes the
    // package document's record once the document has been read, before its
    // manifest is kept, in one of the fields an entry is made of: where its
    // local header is, the size it declares, the bytes it stores. The record
    // as it is now is the entry, not the one held from before the change.
    // `_ChangingBytes` makes the change as the document's last stored byte
    // is read, so it lands in that window whatever opening awaits.
    const String opfPath = 'OEBPS/content.opf';

    /// [book] opened while [change] alters the package document's record,
    /// at [record] in [data], after the document has been read.
    Future<EpubBookRef> openChanging(
        Uint8List book, void Function(ByteData data, int record) change) {
      final ByteData data = ByteData.sublistView(book);
      final int record = _recordOf(book, opfPath);
      final int lastByte = data.getUint32(record + 42, Endian.little) +
          _localFileHeaderLength +
          opfPath.length +
          data.getUint32(record + 20, Endian.little) -
          1;
      return reader.openBook(
          _ChangingBytes(book,
              after: lastByte, change: () => change(data, record)),
          maxEntryBytes: _maxEntryBytes);
    }

    /// The bytes [name] stores in [book], as `_craftZip` wrote them.
    Uint8List storedOf(Uint8List book, String name) {
      final ByteData data = ByteData.sublistView(book);
      final int record = _recordOf(book, name);
      final int start = data.getUint32(record + 42, Endian.little) +
          _localFileHeaderLength +
          utf8.encode(name).length;
      return book.sublist(
          start, start + data.getUint32(record + 20, Endian.little));
    }

    final _CraftedZipEntry chapter =
        _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml));

    test(
        'TC-LIM-72 [Error guessing]: a record moved to another local header '
        'while the book opens is read from there', () async {
      final int length = storedOf(_craftBook(chapter: chapter), opfPath).length;
      final List<int> moved = List<int>.generate(
          length, (int i) => 'NGE-SEED-MOVED '.codeUnitAt(i % 15));
      final Uint8List book =
          _craftBook(chapter: chapter, extra: <_CraftedZipEntry>[
        _CraftedZipEntry.stored('OEBPS/moved.bin', moved),
      ]);
      final int movedHeader = ByteData.sublistView(book)
          .getUint32(_recordOf(book, 'OEBPS/moved.bin') + 42, Endian.little);

      final EpubBookRef bookRef = await openChanging(
          book,
          (ByteData data, int record) =>
              data.setUint32(record + 42, movedHeader, Endian.little));

      expect(bookRef.knownEntrySizes[opfPath], length);
      expect(await bookRef.readEntry(opfPath), moved);
    });

    // The declared size only sizes the buffer a read collects into, so the
    // bytes read are the ones stored either way; the size shows in
    // `knownEntrySizes`.
    test(
        'TC-LIM-72 [Error guessing]: a record that declares another size '
        'while the book opens is known by that size', () async {
      final Uint8List book = _craftBook(chapter: chapter);
      final Uint8List opf = storedOf(book, opfPath);

      final EpubBookRef bookRef = await openChanging(
          book,
          (ByteData data, int record) =>
              data.setUint32(record + 24, opf.length + 8, Endian.little));

      expect(bookRef.knownEntrySizes[opfPath], opf.length + 8);
      expect(await bookRef.readEntry(opfPath), opf);
    });

    test(
        'TC-LIM-72 [Error guessing]: a record that stores fewer bytes while '
        'the book opens is read to its new length', () async {
      final Uint8List book = _craftBook(chapter: chapter);
      final Uint8List opf = storedOf(book, opfPath);

      final EpubBookRef bookRef = await openChanging(
          book,
          (ByteData data, int record) =>
              data.setUint32(record + 20, opf.length - 8, Endian.little));

      expect(bookRef.knownEntrySizes[opfPath], opf.length);
      expect(await bookRef.readEntry(opfPath), opf.sublist(0, opf.length - 8));
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
        final EpubBook book = await reader.readBook(
            _craftBook(chapter: method.value),
            maxEntryBytes: _maxEntryBytes,
            maxTotalBytes: _maxTotalBytes);

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
        final EpubBookRef bookRef = await reader.openBook(
            _craftBook(
              chapter: _CraftedZipEntry.stored(_chapterPath, chapterBytes),
              extra: <_CraftedZipEntry>[
                _CraftedZipEntry(
                  name: 'OEBPS/extra.bin',
                  method: method.value,
                  declaredUncompressedSize: 3,
                  payload: const <int>[0x4E, 0x47, 0x45],
                ),
              ],
            ),
            maxEntryBytes: _maxEntryBytes);

        await expectLater(bookRef.readEntry('OEBPS/extra.bin'),
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
      final EpubBookRef bookRef =
          await reader.openBook(book, maxEntryBytes: _maxEntryBytes);

      expect(
          (await reader.readBook(book,
                  maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes))
              .chapters
              .single
              .htmlContent,
          _chapterXhtml);
      await expectLater(bookRef.readEntry('OEBPS/unused.bin'), _throwsCorrupt);
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
      final EpubBookRef bookRef = await reader.openBook(
          _craftBook(
            chapter: _deflateEntry(_chapterPath,
                Uint8List.sublistView(compressed, 0, compressed.length ~/ 2),
                declaredUncompressedSize: whole.length),
          ),
          maxEntryBytes: _maxEntryBytes);
      final List<int> content = (await bookRef.readEntry(_chapterPath))!;

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
        final EpubBookRef bookRef = await reader.openBook(
            _craftBook(
              chapter: _deflateEntry(_chapterPath,
                  _rawDeflateOf(chapterBytes.length, block: chapterBytes),
                  declaredUncompressedSize: declared.value),
            ),
            maxEntryBytes: _maxEntryBytes);
        final ArchiveFile chapter =
            bookRef.content.html['chapter1.xhtml']!.getContentFileEntry();

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
      final EpubBookRef bookRef =
          await reader.openBook(book, maxEntryBytes: _maxEntryBytes);

      expect((await bookRef.getChapters()).single.readHtmlContent(),
          _throwsCorrupt);
      expect(
          reader.readBook(book,
              maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes),
          _throwsCorrupt);
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

    Future<Uint8List?> later(EpubBookRef bookRef) =>
        bookRef.readEntry(laterPath);

    // TC-LIM-46 [Scenario]: `openBook` reads no entry it does not parse; an
    // entry is read from the bytes when it is asked for. Changed after
    // opening, a stored entry reads as it is then.
    test(
        'TC-LIM-46 [Scenario]: an entry is read from the source when it is '
        'asked for, not when the book is opened', () async {
      final Uint8List bytes = bookWith(_CraftedZipEntry.stored(
          laterPath, utf8.encode('NGE-SEED-READ-LATER')));
      final EpubBookRef bookRef =
          await reader.openBook(bytes, maxEntryBytes: _maxEntryBytes);
      replace(bytes, utf8.encode('NGE-SEED-READ-LATER'),
          utf8.encode('NGE-SEED-READ-AGAIN'));

      expect(await later(bookRef), utf8.encode('NGE-SEED-READ-AGAIN'));
    });

    // TC-LIM-47 [Error guessing]: an entry is inflated only when it is read.
    // Damaged after opening, it fails no other read, and fails its own only
    // when it is read.
    test(
        'TC-LIM-47 [Error guessing]: an entry damaged after opening fails '
        'only when it is read', () async {
      final Uint8List bytes = bookWith(deflatedLater(storedBlock(4)));
      final EpubBookRef bookRef =
          await reader.openBook(bytes, maxEntryBytes: _maxEntryBytes);
      replace(bytes, storedBlock(4), List<int>.filled(9, 0xFF));

      expect(await (await bookRef.getChapters()).single.readHtmlContent(),
          _chapterXhtml);
      await expectLater(
          later(bookRef), throwsA(isA<EpubCorruptArchiveException>()));
    });

    // TC-LIM-48 [Scenario]: nothing about an entry's content is recorded
    // when the book is opened, so a read is of the bytes as they are then,
    // held only to the limits. Changed in place to inflate to fewer bytes,
    // or to more, the entry reads as it now is.
    test(
        'TC-LIM-48 [Scenario]: an entry changed after opening to inflate to '
        'fewer or more bytes reads as it now is', () async {
      final Uint8List shrinking = bookWith(deflatedLater(storedBlock(4)));
      final EpubBookRef shrunk =
          await reader.openBook(shrinking, maxEntryBytes: _maxEntryBytes);
      replace(shrinking, storedBlock(4), storedBlock(2));

      final Uint8List growing = bookWith(deflatedLater(storedBlock(2)));
      final EpubBookRef grown =
          await reader.openBook(growing, maxEntryBytes: _maxEntryBytes);
      replace(growing, storedBlock(2), storedBlock(4));

      expect(await later(shrunk), utf8.encode('NG'));
      expect(await later(grown), utf8.encode('NGE-'));
    });

    // TC-LIM-49 [Scenario]: each read of an entry inflates it from the
    // source. Read twice, it is inflated twice: equal bytes, each read's own.
    // Changed after a read, it reads as it is then, by `readEntry`, and, for
    // an entry the manifest lists, by its `content` and `writeContent`
    // alike. That no read is kept afterwards is
    // `epub_ref_retention_test.dart`'s to pin.
    test(
        'TC-LIM-49 [Scenario]: an entry read twice is inflated twice, from '
        'the source as it is then', () async {
      final Uint8List bytes = _craftBook(
        chapter:
            _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
        listed: <_CraftedZipEntry>[deflatedLater(storedBlock(4))],
      );
      final EpubBookRef bookRef =
          await reader.openBook(bytes, maxEntryBytes: _maxEntryBytes);
      final List<int> first = (await later(bookRef))!;
      final List<int> second = (await later(bookRef))!;
      expect(first, utf8.encode('NGE-'));
      expect(second, first);
      expect(second, isNot(same(first)));

      replace(bytes, storedBlock(4), storedBlock(2));
      final ArchiveFile entry =
          bookRef.content.allFiles['later.bin']!.getContentFileEntry();
      final OutputStream written = OutputStream();
      entry.writeContent(written);

      expect(await later(bookRef), utf8.encode('NG'));
      expect(entry.content, utf8.encode('NG'));
      expect(written.getBytes(), utf8.encode('NG'));
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
        final EpubBookRef cut =
            await reader.openBookFile(path, maxEntryBytes: _maxEntryBytes);
        File(path).openSync(mode: FileMode.append)
          ..truncateSync(book.length ~/ 2)
          ..closeSync();

        await expectLater(
            later(cut), throwsA(isA<EpubCorruptArchiveException>()));

        File(path).writeAsBytesSync(book);
        final EpubBookRef removed =
            await reader.openBookFile(path, maxEntryBytes: _maxEntryBytes);
        File(path).deleteSync();
        await expectLater(later(removed), throwsA(isA<FileSystemException>()));
      });

      // TC-LIM-56 [Scenario]: an entry of a book file is read from the file
      // each time: changed in place after a read, it reads as it is then.
      test(
          'TC-LIM-56 [Scenario]: an entry of a file read twice is read from '
          'the file as it is then', () async {
        final Uint8List book = bookWith(deflatedLater(storedBlock(4)));
        File(path).writeAsBytesSync(book);
        final EpubBookRef bookRef =
            await reader.openBookFile(path, maxEntryBytes: _maxEntryBytes);
        expect(await later(bookRef), utf8.encode('NGE-'));

        replace(book, storedBlock(4), storedBlock(2));
        File(path).writeAsBytesSync(book);

        expect(await later(bookRef), utf8.encode('NG'));
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

        final EpubBookRef fromFile =
            await reader.openBookFile(path, maxEntryBytes: _maxEntryBytes);
        expect(fromFile,
            await reader.openBook(bytes, maxEntryBytes: _maxEntryBytes));
        expect(await later(fromFile), big);
        expect(
            await reader.readBookFile(path,
                maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes),
            await reader.readBook(bytes,
                maxEntryBytes: _maxEntryBytes, maxTotalBytes: _maxTotalBytes));
      });

      // TC-LIM-52 [Scenario]: a central directory of 10,000 records, over
      // 700 KiB, is read from a file record by record, running across the
      // end of one window into the next many times. Every record is read,
      // as from bytes (TC-LIM-59), and an entry deep in the file reads.
      test(
          'TC-LIM-52 [Scenario]: a central directory spanning many windows '
          'of its file is read whole', () async {
        File(path).writeAsBytesSync(_craftBook(
          chapter:
              _CraftedZipEntry.stored(_chapterPath, utf8.encode(_chapterXhtml)),
          extra: <_CraftedZipEntry>[
            for (int i = 0; i < _manyEntries; i++)
              _CraftedZipEntry.stored(
                  'NGE-SEED-$i.txt', utf8.encode('NGE-SEED-$i')),
          ],
        ));

        final EpubBookRef bookRef =
            await reader.openBookFile(path, maxEntryBytes: _maxEntryBytes);
        expect(bookRef.knownEntrySizes, hasLength(5));
        expect(await bookRef.readEntry('NGE-SEED-9999.txt'),
            utf8.encode('NGE-SEED-9999'));
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

/// The two limits a `readBook` takes.
/// [_bytes] as a list, changed by [_change] once the byte at [_after] has
/// been read for the first time.
final class _ChangingBytes extends ListBase<int> {
  _ChangingBytes(this._bytes,
      {required int after, required void Function() change})
      : _after = after,
        _change = change;

  final Uint8List _bytes;
  final int _after;
  final void Function() _change;
  bool _changed = false;

  @override
  int get length => _bytes.length;

  @override
  set length(int newLength) => throw UnsupportedError('A fixed length.');

  @override
  int operator [](int index) {
    final int byte = _bytes[index];
    if (index == _after && !_changed) {
      _changed = true;
      _change();
    }
    return byte;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Read only.');
}

class _Limits {
  const _Limits(this.entry, this.total);

  final int? entry;
  final int? total;
}
