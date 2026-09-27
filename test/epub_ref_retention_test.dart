// Whether an `EpubBookRef` keeps what it reads, asked of the collector: each
// case reads through a ref, drops what the read returned, forces a full
// collection through the VM service, and asks a `WeakReference` whether the
// bytes are still alive. Only a reference held somewhere keeps them, so a
// ref, or its archive, keeping the last read would keep them alive.
//
// The VM service is started from inside the test process, which runs from
// source. A compiled executable has none, so this is not part of the AOT
// memory probe.
import 'dart:developer';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/ref_entities/epub_byte_content_file_ref.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart' hide Isolate;
import 'package:vm_service/vm_service_io.dart';

import 'support/epub_fixture.dart';

/// A one-chapter book whose cover image is flagged in its manifest.
Uint8List _bookWithCover() => buildEpubArchive(
      opfPath: 'OEBPS/content.opf',
      textEntries: <String, String>{
        'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:NGE-SEED-RETAIN</dc:identifier>'
            '<dc:title>NGE-SEED Retention Book</dc:title>'
            '</metadata>'
            '<manifest>'
            '<item id="ncx" href="toc.ncx" '
            'media-type="application/x-dtbncx+xml"/>'
            '<item id="ch1" href="chapter1.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '<item id="img" href="cover.png" media-type="image/png" '
            'properties="cover-image"/>'
            '</manifest>'
            '<spine toc="ncx"><itemref idref="ch1"/></spine>'
            '</package>',
        'OEBPS/toc.ncx': '<?xml version="1.0" encoding="UTF-8"?>'
            '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" '
            'version="2005-1">'
            '<head/><docTitle><text>NGE-SEED Retention Book</text></docTitle>'
            '<navMap><navPoint id="np-1" playOrder="1">'
            '<navLabel><text>NGE-SEED Chapter</text></navLabel>'
            '<content src="chapter1.xhtml"/>'
            '</navPoint></navMap>'
            '</ncx>',
        'OEBPS/chapter1.xhtml': seedXhtml('NGE-SEED-RETAIN-CH1'),
      },
      binaryEntries: <String, List<int>>{'OEBPS/cover.png': seedPngBytes()},
    );

void main() {
  late VmService service;
  late String isolateId;
  late EpubBookRef bookRef;

  setUpAll(() async {
    final ServiceProtocolInfo info =
        await Service.controlWebServer(enable: true, silenceOutput: true);
    final Uri server = info.serverUri!;
    service = await vmServiceConnectUri(
        server.replace(scheme: 'ws', pathSegments: <String>[
      ...server.pathSegments.where((String s) => s.isNotEmpty),
      'ws',
    ]).toString());
    // The isolate this test runs in, found by its name: the VM service's id
    // for it is only asked of `Service` directly from SDK 3.2.
    isolateId = (await service.getVM())
        .isolates!
        .singleWhere(
            (IsolateRef isolate) => isolate.name == Isolate.current.debugName)
        .id!;
    bookRef = await const EpubReader().openBook(_bookWithCover());
  });

  tearDownAll(() async {
    await service.dispose();
  });

  /// Whether what [read] returns is still alive after it is dropped and a
  /// full collection has run.
  Future<bool> survives(Future<Object?> Function() read) async {
    final WeakReference<Object> weak = WeakReference<Object>((await read())!);
    await service.getAllocationProfile(isolateId, gc: true);
    return weak.target != null;
  }

  EpubByteContentFileRef cover() => bookRef.content.images['cover.png']!;

  // TC-RET-1 [Scenario]: the collector is able to tell. An entry
  // `package:archive` decodes keeps its content once read, for as long as
  // the archive lives: the same collection leaves it alive.
  test('TC-RET-1 [Scenario]: content an archive keeps survives a collection',
      () async {
    final Archive archive = ZipDecoder().decodeBytes(_bookWithCover());

    expect(
        await survives(
            () async => archive.findFile('OEBPS/cover.png')!.content),
        isTrue);
    expect(archive.findFile('OEBPS/cover.png'), isNotNull);
  });

  // TC-RET-2 [Scenario]: nothing in a ref keeps what a read returned. Once
  // the caller drops it, a full collection frees it, whichever way it was
  // read: as bytes, through the stream methods, as the cover, or as the
  // content of an entry of `epubArchive()`. The ref itself is alive
  // throughout.
  final Map<String, Future<Object?> Function()> reads =
      <String, Future<Object?> Function()>{
    'readContentAsBytes': () => cover().readContentAsBytes(),
    'getContentStream': () async => cover().getContentStream(),
    'openContentStream': () async =>
        cover().openContentStream(cover().getContentFileEntry()),
    'readCoverBytes': () => bookRef.readCoverBytes(),
    'ArchiveFile.content': () async =>
        bookRef.epubArchive().findFile('OEBPS/cover.png')!.content,
  };
  for (final MapEntry<String, Future<Object?> Function()> read
      in reads.entries) {
    test(
        'TC-RET-2 [Scenario]: bytes read by ${read.key} are freed once the '
        'caller drops them', () async {
      expect(await survives(read.value), isFalse);
      expect(bookRef.title, 'NGE-SEED Retention Book');
    });
  }
}
