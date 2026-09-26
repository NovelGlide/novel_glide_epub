// Run by `epub_archive_memory_test.dart` in a process of its own, since the
// high-water mark of memory it reports is the process's, and any test run
// before it in the same process could already have raised it.
//
// Usage: archive_memory_probe.dart <case> <scratch directory>
// Builds its fixture first, then prints how many MiB the process's peak
// memory grew by across the one call the case is about.
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
/// close to the data's size is ever held in memory.
void _writeZip(String path, List<_ProbeEntry> entries) {
  final RandomAccessFile file = File(path).openSync(mode: FileMode.write);
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
  final ByteData end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, records.length, Endian.little)
    ..setUint32(16, directoryOffset, Endian.little);
  file
    ..writeFromSync(records)
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

/// A readable one-chapter book with a 200 MiB stored audio file in its
/// manifest.
List<_ProbeEntry> _bookWithAudio() {
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
    _ProbeEntry('OEBPS/audio.mp3', _randomMib(), repeat: 200),
  ];
}

/// The call [probeCase] measures, its fixture already built at [path].
Future<Future<Object?> Function()> _prepare(
    String probeCase, String path) async {
  switch (probeCase) {
    // A 128 MiB stored entry, opened from its file.
    case 'file':
      _writeZip(
          path, <_ProbeEntry>[_ProbeEntry('x', _randomMib(), repeat: 128)]);
      return () => const EpubReader().openBookFile(path);
    // An entry inflating to the 256 MiB limit, opened from bytes.
    case 'inflate':
      final Uint8List deflated = _deflatedZeros(256 * _oneMib);
      _writeZip(path, <_ProbeEntry>[
        _ProbeEntry('x', deflated, method: 8, uncompressedSize: 256 * _oneMib),
      ]);
      final Uint8List bytes = File(path).readAsBytesSync();
      return () => const EpubReader().openBook(bytes);
    // The 200 MiB audio file of an opened book, read as bytes.
    default:
      _writeZip(path, _bookWithAudio());
      final EpubBookRef bookRef = await const EpubReader().openBookFile(path);
      return () => bookRef.content.allFiles['audio.mp3']!.readContentAsBytes();
  }
}

Future<void> main(List<String> args) async {
  final Future<Object?> Function() measured =
      await _prepare(args[0], '${args[1]}/probe.zip');
  final int before = ProcessInfo.maxRss;
  try {
    await measured();
  } on EpubMissingArchiveEntryException catch (expected) {
    // The archive is valid but holds no book; opening it got that far.
    stderr.writeln(expected);
  }
  stdout.writeln((ProcessInfo.maxRss - before) ~/ _oneMib);
}
