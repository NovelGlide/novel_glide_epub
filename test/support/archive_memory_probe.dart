// Run by `epub_archive_memory_test.dart` in a process of its own, since the
// high-water mark of memory it reports is the process's, and any test run
// before it in the same process could already have raised it.
//
// Usage: archive_memory_probe.dart <case> <scratch directory>
// Builds its fixture first, unless the scratch directory already holds it
// from an earlier run, then prints how many MiB the process's peak
// memory grew by across the one call the case is about. `entries:<n>` opens
// a book of n more entries than its own.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:novel_glide_epub/novel_glide_epub.dart';

const int _oneMib = 1024 * 1024;

/// One entry of a probe ZIP: [payload] written [repeat] times as its data,
/// stored or deflated by [method], declaring [uncompressedSize] or, when that
/// is not given, its data's length.
class _ProbeEntry {
  const _ProbeEntry(
    this.name,
    this.payload, {
    this.method = 0,
    this.repeat = 1,
    int? uncompressedSize,
  }) : _uncompressedSize = uncompressedSize;

  final String name;
  final List<int> payload;
  final int method;
  final int repeat;
  final int? _uncompressedSize;

  int get dataLength => payload.length * repeat;
  int get uncompressedSize => _uncompressedSize ?? dataLength;
}

/// [entries] in a ZIP written to [path], a payload at a time, so nothing
/// close to the data's size is ever held in memory, after [gap] bytes that
/// no entry holds and nothing writes: a hole the file system keeps sparse.
/// Past 65,535 entries, the count is in a zip64 end record, as a writer
/// puts it.
void _writeZip(String path, List<_ProbeEntry> entries, {int gap = 0}) {
  final RandomAccessFile file = File(path).openSync(mode: FileMode.write)
    ..setPositionSync(gap);
  final BytesBuilder directory = BytesBuilder(copy: false);
  for (final _ProbeEntry entry in entries) {
    final List<int> name = utf8.encode(entry.name);
    final int offset = file.positionSync();
    final ByteData local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(8, entry.method, Endian.little)
      ..setUint32(18, entry.dataLength, Endian.little)
      ..setUint32(22, entry.uncompressedSize, Endian.little)
      ..setUint16(26, name.length, Endian.little);
    file
      ..writeFromSync(local.buffer.asUint8List())
      ..writeFromSync(name);
    for (int i = 0; i < entry.repeat; i++) {
      file.writeFromSync(entry.payload);
    }
    final ByteData record = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(10, entry.method, Endian.little)
      ..setUint32(20, entry.dataLength, Endian.little)
      ..setUint32(24, entry.uncompressedSize, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    directory
      ..add(record.buffer.asUint8List())
      ..add(name);
  }
  final int directoryOffset = file.positionSync();
  final Uint8List records = directory.takeBytes();
  file.writeFromSync(records);
  final bool zip64 = entries.length > 0xFFFF;
  if (zip64) {
    final int record = file.positionSync();
    final ByteData tail = ByteData(56 + 20)
      ..setUint32(0, 0x06064b50, Endian.little)
      ..setUint64(4, 44, Endian.little)
      ..setUint16(12, 45, Endian.little)
      ..setUint16(14, 45, Endian.little)
      ..setUint64(24, entries.length, Endian.little)
      ..setUint64(32, entries.length, Endian.little)
      ..setUint64(40, records.length, Endian.little)
      ..setUint64(48, directoryOffset, Endian.little)
      ..setUint32(56, 0x07064b50, Endian.little)
      ..setUint64(56 + 8, record, Endian.little)
      ..setUint32(56 + 16, 1, Endian.little);
    file.writeFromSync(tail.buffer.asUint8List());
  }
  final int count = zip64 ? 0xFFFF : entries.length;
  final ByteData end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, count, Endian.little)
    ..setUint16(10, count, Endian.little)
    ..setUint32(12, records.length, Endian.little)
    ..setUint32(16, directoryOffset, Endian.little);
  file
    ..writeFromSync(end.buffer.asUint8List())
    ..closeSync();
}

/// A MiB of random bytes. Data meant to show in a process's memory is
/// random, not zeros: pages of zeros barely count towards it.
List<int> _randomMib() {
  final Random random = Random(0x4E47);
  return List<int>.generate(_oneMib, (int i) => random.nextInt(256));
}

/// A raw-deflate stream of [length] zeros, built a MiB at a time.
Uint8List _deflatedZeros(int length) {
  final RawZLibFilter filter = RawZLibFilter.deflateFilter(raw: true);
  final BytesBuilder out = BytesBuilder(copy: false);
  final Uint8List block = Uint8List(_oneMib);
  for (int left = length; left > 0; left -= _oneMib) {
    filter.process(block, 0, left < _oneMib ? left : _oneMib);
    for (List<int>? c = filter.processed(flush: false);
        c != null;
        c = filter.processed(flush: false)) {
      out.add(c);
    }
  }
  for (List<int>? c = filter.processed(end: true);
      c != null;
      c = filter.processed(end: true)) {
    out.add(c);
  }
  return out.takeBytes();
}

/// A readable one-chapter book with [audio] as `OEBPS/audio.mp3` in its
/// manifest, and [extra] entries nothing in it points at.
List<_ProbeEntry> _bookWithAudio(_ProbeEntry audio,
    [List<_ProbeEntry> extra = const <_ProbeEntry>[]]) {
  _ProbeEntry text(String name, String content) =>
      _ProbeEntry(name, utf8.encode(content));
  return <_ProbeEntry>[
    text('mimetype', 'application/epub+zip'),
    text(
        'META-INF/container.xml',
        '<?xml version="1.0" encoding="UTF-8"?><container version="1.0" '
            'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles>'
            '</container>'),
    text(
        'OEBPS/content.opf',
        '<?xml version="1.0" encoding="UTF-8"?><package '
            'xmlns="http://www.idpf.org/2007/opf" version="2.0" '
            'unique-identifier="uid"><metadata '
            'xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier '
            'id="uid">urn:uuid:NGE-SEED-PROBE</dc:identifier><dc:title>'
            'NGE-SEED Probe</dc:title></metadata><manifest><item id="ncx" '
            'href="toc.ncx" media-type="application/x-dtbncx+xml"/><item '
            'id="ch1" href="chapter1.xhtml" '
            'media-type="application/xhtml+xml"/><item id="audio" '
            'href="audio.mp3" media-type="audio/mpeg"/></manifest><spine '
            'toc="ncx"><itemref idref="ch1"/></spine></package>'),
    text(
        'OEBPS/toc.ncx',
        '<?xml version="1.0" encoding="UTF-8"?><ncx '
            'xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
            '<head/><docTitle><text>NGE-SEED Probe</text></docTitle><navMap>'
            '<navPoint id="np1" playOrder="1"><navLabel><text>One</text>'
            '</navLabel><content src="chapter1.xhtml"/></navPoint></navMap>'
            '</ncx>'),
    text('OEBPS/chapter1.xhtml', '<html><body><p>NGE-SEED</p></body></html>'),
    audio,
    ...extra,
  ];
}

/// Runs [write] unless [path] already holds the fixture it writes: a run
/// whose scratch directory holds one from an earlier run builds nothing, so
/// the peak it reports is the call's alone.
void _build(String path, void Function() write) {
  if (!File(path).existsSync()) {
    write();
  }
}

/// The limit on one entry a caller reading untrusted files might pass.
const int _maxEntryBytes = 256 * _oneMib;

/// An opened book's `audio.mp3`, read as bytes.
Future<Object?> _readAudio(EpubBookRef bookRef) =>
    bookRef.content.allFiles['audio.mp3']!.readContentAsBytes();

/// A book whose audio entry declares 1 KiB and inflates to [length] zeros,
/// opened from [path] with each entry held to [_maxEntryBytes].
Future<EpubBookRef> _openBomb(String path, int length) async {
  _build(
      path,
      () => _writeZip(
          path,
          _bookWithAudio(_ProbeEntry('OEBPS/audio.mp3', _deflatedZeros(length),
              method: 8, uncompressedSize: 1024))));
  return const EpubReader().openBookFile(path, maxEntryBytes: _maxEntryBytes);
}

/// A book whose 200 MiB stored audio entry holds random bytes, opened from
/// [path] with each entry held to [maxEntryBytes].
Future<EpubBookRef> _openBigAudio(String path, int? maxEntryBytes) {
  _build(
      path,
      () => _writeZip(
          path,
          _bookWithAudio(
              _ProbeEntry('OEBPS/audio.mp3', _randomMib(), repeat: 200))));
  return const EpubReader().openBookFile(path, maxEntryBytes: maxEntryBytes);
}

/// 4096 central-directory records written to [path], every one of an empty
/// entry whose local header is the one at offset 0, with a name and an
/// extra field of 65,535 bytes each.
void _writeSharedLocalHeaderZip(String path) {
  const int fieldLength = 0xFFFF;
  const int records = 4096;
  const int directory = 30 + 2 * fieldLength;
  const int end = directory + 46 * records;
  final Uint8List bytes = Uint8List(end + 22)..fillRange(30, directory, 0x4E);
  final ByteData data = ByteData.sublistView(bytes)
    ..setUint32(0, 0x04034b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(26, fieldLength, Endian.little)
    ..setUint16(28, fieldLength, Endian.little)
    ..setUint32(end, 0x06054b50, Endian.little)
    ..setUint16(end + 8, records, Endian.little)
    ..setUint16(end + 10, records, Endian.little)
    ..setUint32(end + 12, 46 * records, Endian.little)
    ..setUint32(end + 16, directory, Endian.little);
  for (int record = directory; record < end; record += 46) {
    data.setUint32(record, 0x02014b50, Endian.little);
  }
  File(path).writeAsBytesSync(bytes);
}

/// [records] central-directory records written to [path], and nothing else
/// but the one empty local header they all point at: the smallest file that
/// opens to that many entries. Each record is 46 bytes and a distinct name
/// of at most five digits, and stores nothing.
void _writeRecordsOnlyZip(String path, int records) {
  final RandomAccessFile file = File(path).openSync(mode: FileMode.write);
  file.writeFromSync((ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little))
      .buffer
      .asUint8List());
  final BytesBuilder block = BytesBuilder(copy: false);
  for (int i = 0; i < records; i++) {
    final List<int> name = utf8.encode('$i');
    block
      ..add((ByteData(46)
            ..setUint32(0, 0x02014b50, Endian.little)
            ..setUint16(4, 20, Endian.little)
            ..setUint16(6, 20, Endian.little)
            ..setUint16(28, name.length, Endian.little))
          .buffer
          .asUint8List())
      ..add(name);
    if (block.length >= _oneMib) {
      file.writeFromSync(block.takeBytes());
    }
  }
  file.writeFromSync(block.takeBytes());
  final int directoryLength = file.positionSync() - 30;
  file
    ..writeFromSync((ByteData(22)
          ..setUint32(0, 0x06054b50, Endian.little)
          ..setUint16(8, records & 0xFFFF, Endian.little)
          ..setUint16(10, records & 0xFFFF, Endian.little)
          ..setUint32(12, directoryLength, Endian.little)
          ..setUint32(16, 30, Endian.little))
        .buffer
        .asUint8List())
    ..closeSync();
}

/// The call [probeCase] measures, its fixture built at [path] first unless
/// it is already there.
Future<Future<Object?> Function()> _prepare(
    String probeCase, String path) async {
  switch (probeCase.split(':')) {
    // A 128 MiB stored entry, opened from its file.
    case <String>['file']:
      _build(
          path,
          () => _writeZip(path,
              <_ProbeEntry>[_ProbeEntry('x', _randomMib(), repeat: 128)]));
      return () => const EpubReader().openBookFile(path, maxEntryBytes: null);
    // A readable book after a 1.5 GiB hole, opened from its file.
    case <String>['large']:
      _build(
          path,
          () => _writeZip(
              path,
              _bookWithAudio(
                  _ProbeEntry('OEBPS/audio.mp3', utf8.encode('NGE-SEED'))),
              gap: 1536 * _oneMib));
      return () => const EpubReader().openBookFile(path, maxEntryBytes: null);
    // A readable book with n more one-byte entries, opened from its file.
    case <String>['entries', final String count]:
      _build(
          path,
          () => _writeZip(
              path,
              _bookWithAudio(
                  _ProbeEntry('OEBPS/audio.mp3', utf8.encode('NGE-SEED')),
                  <_ProbeEntry>[
                    for (int i = 0; i < int.parse(count); i++)
                      _ProbeEntry('OEBPS/extra/$i.txt', const <int>[0x4E]),
                  ])));
      return () => const EpubReader().openBookFile(path, maxEntryBytes: null);
    // n records and nothing else, opened from its file.
    case <String>['records', final String count]:
      _build(path, () => _writeRecordsOnlyZip(path, int.parse(count)));
      return () => const EpubReader().openBookFile(path, maxEntryBytes: null);
    // 4096 records sharing one 128 KiB local header, opened from its file.
    case <String>['shared']:
      _build(path, () => _writeSharedLocalHeaderZip(path));
      return () => const EpubReader().openBookFile(path, maxEntryBytes: null);
    // An audio file declaring 1 KiB and inflating to 1 GiB of zeros, read as
    // bytes from a book opened with a 256 MiB limit.
    case <String>['bomb']:
      final EpubBookRef bookRef = await _openBomb(path, 1024 * _oneMib);
      return () => _readAudio(bookRef);
    // The same, inflating to 4 GiB.
    case <String>['bomb4g']:
      final EpubBookRef bookRef = await _openBomb(path, 4096 * _oneMib);
      return () => _readAudio(bookRef);
    // A 200 MiB stored audio file, read as bytes five times in a row from
    // one book opened with a 256 MiB limit, each read's bytes dropped before
    // the next.
    case <String>['reread']:
      final EpubBookRef bookRef = await _openBigAudio(path, _maxEntryBytes);
      return () async {
        for (int i = 0; i < 5; i++) {
          await _readAudio(bookRef);
        }
        return null;
      };
    // A 200 MiB stored audio file, read as bytes from a book opened with no
    // limit.
    case <String>['read-unlimited']:
      final EpubBookRef bookRef = await _openBigAudio(path, null);
      return () => _readAudio(bookRef);
    // A 200 MiB audio file of deflated zeros, declaring its size, read as
    // bytes from a book opened with no limit.
    case <String>['read-deflated-unlimited']:
      _build(
          path,
          () => _writeZip(
              path,
              _bookWithAudio(_ProbeEntry(
                  'OEBPS/audio.mp3', _deflatedZeros(200 * _oneMib),
                  method: 8, uncompressedSize: 200 * _oneMib))));
      final EpubBookRef bookRef =
          await const EpubReader().openBookFile(path, maxEntryBytes: null);
      return () => _readAudio(bookRef);
    // A 200 MiB stored audio file, read as bytes from a book opened with a
    // 256 MiB limit.
    default:
      final EpubBookRef bookRef = await _openBigAudio(path, _maxEntryBytes);
      return () => _readAudio(bookRef);
  }
}

Future<void> main(List<String> args) async {
  final Future<Object?> Function() measured =
      await _prepare(args[0], '${args[1]}/probe.zip');
  final int before = ProcessInfo.maxRss;
  try {
    await measured();
  } on EpubMissingArchiveEntryException catch (expected) {
    // An archive that holds no book, read as far as its missing container.
    stderr.writeln(expected);
  } on EpubArchiveTooLargeException catch (expected) {
    // The bomb, refused part-way.
    stderr.writeln(expected);
  }
  stdout.writeln((ProcessInfo.maxRss - before) ~/ _oneMib);
}
