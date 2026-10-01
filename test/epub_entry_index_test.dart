// What an opened book keeps of its ZIP directory, and how it finds the rest.
//
// Opening keeps `mimetype`, every `META-INF/` entry, the package document and
// every file its manifest lists, and reads every other record without keeping
// it. `EpubBookRef.readEntry` reads any entry by its archive name: a kept one
// at once, any other by one more pass over the directory, kept from then on.
// `EpubBookRef.knownEntrySizes` lists what opening kept.
//
// Which reads go through the directory is observed from outside: the book's
// bytes are changed after opening so that a pass over the directory would no
// longer find a name, which a read that does not look there never notices.
//
// Equivalent mutants, documented rather than chased: none known.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart' show ListEquality;
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

const EpubReader _reader = EpubReader();

/// A two-chapter book whose stylesheet points at an image its manifest does
/// not list, with [extra] entries nothing points at, and with [manifestExtra]
/// added to its manifest. Its package document is at [opfPath].
Uint8List _book({
  String opfPath = 'OEBPS/content.opf',
  String manifestExtra = '',
  Map<String, List<int>> extra = const <String, List<int>>{},
  Map<String, String> metaInf = const <String, String>{},
}) {
  final String opfDirectory = opfPath.substring(0, opfPath.lastIndexOf('/'));
  return buildEpubArchive(
    opfPath: opfPath,
    textEntries: <String, String>{
      ...metaInf,
      opfPath: '<?xml version="1.0" encoding="UTF-8"?>'
          '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
          'unique-identifier="uid">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="uid">urn:uuid:NGE-SEED-INDEX</dc:identifier>'
          '<dc:title>NGE-SEED Index Book</dc:title>'
          '</metadata>'
          '<manifest>'
          '<item id="ncx" href="toc.ncx" '
          'media-type="application/x-dtbncx+xml"/>'
          '<item id="ch1" href="chapter1.xhtml" '
          'media-type="application/xhtml+xml"/>'
          '<item id="ch2" href="Text/chapter%202.xhtml" '
          'media-type="application/xhtml+xml"/>'
          '<item id="css" href="style.css" media-type="text/css"/>'
          '$manifestExtra'
          '</manifest>'
          '<spine toc="ncx"><itemref idref="ch1"/><itemref idref="ch2"/>'
          '</spine>'
          '</package>',
      '$opfDirectory/toc.ncx': _ncx('NGE-SEED Index Book'),
      '$opfDirectory/chapter1.xhtml': seedXhtml('NGE-SEED-INDEX-CH1'),
      '$opfDirectory/Text/chapter 2.xhtml': seedXhtml('NGE-SEED-INDEX-CH2'),
      '$opfDirectory/style.css': 'body { background: url(images/bg.png); }',
    },
    binaryEntries: <String, List<int>>{
      '$opfDirectory/images/bg.png': seedPngBytes(),
      ...extra,
    },
  );
}

String _ncx(String title) => '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head/><docTitle><text>$title</text></docTitle>'
    '<navMap>'
    '<navPoint id="np-1" playOrder="1">'
    '<navLabel><text>NGE-SEED One</text></navLabel>'
    '<content src="chapter1.xhtml"/></navPoint>'
    '<navPoint id="np-2" playOrder="2">'
    '<navLabel><text>NGE-SEED Two</text></navLabel>'
    '<content src="Text/chapter%202.xhtml"/></navPoint>'
    '</navMap>'
    '</ncx>';

/// Where the central directory of [zip] starts, by its end record, which
/// `ZipEncoder` writes with no comment.
int _directoryOf(Uint8List zip) =>
    ByteData.sublistView(zip).getUint32(zip.length - 22 + 16, Endian.little);

/// Where the name of [zip]'s central-directory record named [name] starts.
int _recordNameOf(Uint8List zip, String name) {
  final List<int> bytes = utf8.encode(name);
  for (int at = _directoryOf(zip); at <= zip.length - bytes.length; at++) {
    if (const ListEquality<int>()
        .equals(Uint8List.sublistView(zip, at, at + bytes.length), bytes)) {
      return at;
    }
  }
  throw StateError('No record named $name');
}

/// [zip] with the central-directory record named [from] renamed [to], a
/// name of the same length; nothing else changes.
void _rename(Uint8List zip, String from, String to) {
  expect(to.length, from.length);
  zip.setAll(_recordNameOf(zip, from), utf8.encode(to));
}

/// [zip] with [count] more central-directory records after its own, each
/// of an empty stored entry named `x/<i>` that points at the first local
/// header, and nothing else added: the records are 46 bytes and a name each,
/// written straight into one buffer, so a million cost about 50 MiB and a
/// few hundred milliseconds.
Uint8List _withRecords(Uint8List zip, int count) {
  final int end = zip.length - 22;
  int extraLength = 0;
  for (int i = 0; i < count; i++) {
    extraLength += 46 + 2 + '$i'.length;
  }
  final Uint8List bytes = Uint8List(zip.length + extraLength)
    ..setAll(0, Uint8List.sublistView(zip, 0, end));
  final ByteData data = ByteData.sublistView(bytes);
  int at = end;
  for (int i = 0; i < count; i++) {
    final String name = 'x/$i';
    data
      ..setUint32(at, 0x02014b50, Endian.little)
      ..setUint16(at + 4, 20, Endian.little)
      ..setUint16(at + 6, 20, Endian.little)
      ..setUint16(at + 28, name.length, Endian.little);
    for (int c = 0; c < name.length; c++) {
      bytes[at + 46 + c] = name.codeUnitAt(c);
    }
    at += 46 + name.length;
  }
  bytes.setAll(at, Uint8List.sublistView(zip, end));
  final int directory = _directoryOf(zip);
  data.setUint32(at + 12, at - directory, Endian.little);
  return bytes;
}

final Matcher _throwsTooLarge = throwsA(isA<EpubArchiveTooLargeException>());

/// The `maxEntryBytes` a book is opened with, and the `maxBytes` one read of
/// it passes.
class _Limits {
  const _Limits(this.entry, this.read);

  final int? entry;
  final int? read;

  @override
  String toString() => 'maxEntryBytes $entry, maxBytes $read';
}

void main() {
  group('what opening keeps', () {
    // TC-IDX-1 [Scenario]: opening keeps `mimetype`, every `META-INF/`
    // entry, the package document, and each file the manifest lists that
    // the archive holds, under its full name, with the size it declares. An
    // item whose file is missing adds nothing, and nor do the entries the
    // manifest leaves out.
    test(
        'TC-IDX-1 [Scenario]: knownEntrySizes lists META-INF, mimetype, the '
        'package document and the manifest files present', () async {
      final Uint8List zip = _book(
        manifestExtra: '<item id="gone" href="gone.png" '
            'media-type="image/png"/>',
        metaInf: <String, String>{
          'META-INF/com.apple.ibooks.display-options.xml': '<display/>',
        },
        extra: <String, List<int>>{'extras/notes.txt': utf8.encode('NGE')},
      );
      final Archive whole = ZipDecoder().decodeBytes(zip);
      int sizeOf(String name) => whole.findFile(name)!.size;
      final EpubBookRef bookRef =
          await _reader.openBook(zip, maxEntryBytes: null);

      expect(bookRef.knownEntrySizes, <String, int>{
        for (final String name in <String>[
          'mimetype',
          'META-INF/container.xml',
          'META-INF/com.apple.ibooks.display-options.xml',
          'OEBPS/content.opf',
          'OEBPS/toc.ncx',
          'OEBPS/chapter1.xhtml',
          'OEBPS/Text/chapter 2.xhtml',
          'OEBPS/style.css',
        ])
          name: sizeOf(name),
      });
      expect(() => bookRef.knownEntrySizes['mimetype'] = 0,
          throwsUnsupportedError);
    });

    // TC-IDX-2 [Boundary]: a package document inside `META-INF/` is kept by
    // the first pass, and found there.
    test(
        'TC-IDX-2 [Boundary]: a package document in META-INF opens, and is '
        'kept once', () async {
      final EpubBookRef bookRef = await _reader.openBook(
          _book(opfPath: 'META-INF/book/content.opf'),
          maxEntryBytes: null);

      expect(bookRef.title, 'NGE-SEED Index Book');
      expect(bookRef.knownEntrySizes.keys,
          containsAll(<String>['META-INF/book/content.opf', 'mimetype']));
      expect(await bookRef.content.html['chapter1.xhtml']!.readContentAsText(),
          seedXhtml('NGE-SEED-INDEX-CH1'));
    });

    // TC-IDX-3 [Scenario]: a book whose directory holds 1,000,000 more
    // records than its own, zero-length and listed nowhere, about 50 MiB of
    // directory, opens and reads its chapters, keeping only its own entries.
    // The records are written straight into the bytes (`_withRecords`), so
    // building the file costs a fraction of opening it. What opening it
    // costs in memory is TC-MEM-11's to pin.
    test(
        'TC-IDX-3 [Scenario]: a book with 1,000,000 more records opens and '
        'reads its chapters', () async {
      final Uint8List zip = _withRecords(_book(), 1000000);
      final EpubBookRef bookRef =
          await _reader.openBook(zip, maxEntryBytes: 1024 * 1024);

      expect(bookRef.knownEntrySizes, hasLength(7));
      final List<EpubChapterRef> chapters = await bookRef.getChapters();
      expect(await chapters.first.readHtmlContent(),
          seedXhtml('NGE-SEED-INDEX-CH1'));
      expect(await chapters.last.readHtmlContent(),
          seedXhtml('NGE-SEED-INDEX-CH2'));
      expect(await bookRef.readEntry('x/999999'), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    // TC-IDX-4 [Error guessing]: a record names its entry with `\` where
    // it should write `/`, as books zipped on Windows do. It is matched as
    // `package:archive` names it, with each `\` read as a `/`: kept when the
    // manifest lists it, found when it does not.
    test(
        'TC-IDX-4 [Error guessing]: a record naming its entry with '
        'backslashes is kept and found by its slashed name', () async {
      final Uint8List zip = _book();
      _rename(zip, 'OEBPS/chapter1.xhtml', r'OEBPS\chapter1.xhtml');
      _rename(zip, 'OEBPS/images/bg.png', r'OEBPS\images\bg.png');
      final EpubBookRef bookRef =
          await _reader.openBook(zip, maxEntryBytes: null);

      expect(bookRef.knownEntrySizes, contains('OEBPS/chapter1.xhtml'));
      expect(await bookRef.content.html['chapter1.xhtml']!.readContentAsText(),
          seedXhtml('NGE-SEED-INDEX-CH1'));
      expect(await bookRef.readEntry('OEBPS/images/bg.png'), seedPngBytes());
    });

    // TC-IDX-5 [Error guessing]: the table of contents is looked up
    // regardless of case, as it always was, so an archive spelling it in
    // another case than the manifest still opens. Of the entries matching
    // it but for case, the first in the directory is kept, and only it:
    // however many a crafted directory spells, each name the manifest
    // lists keeps one more entry at most.
    test(
        'TC-IDX-5 [Error guessing]: a table of contents spelled in another '
        'case is kept, the first spelling only', () async {
      final Uint8List zip = _book(extra: <String, List<int>>{
        'OEBPS/TOC.NCX': utf8.encode(_ncx('NGE-SEED Upper')),
        'OEBPS/Toc.Ncx': utf8.encode(_ncx('NGE-SEED Mixed')),
      });
      _rename(zip, 'OEBPS/toc.ncx', 'OEBPS/tOC.NCx');
      final EpubBookRef bookRef =
          await _reader.openBook(zip, maxEntryBytes: null);

      expect(bookRef.schema.navigation.docTitle.titles,
          <String>['NGE-SEED Index Book']);
      expect(bookRef.knownEntrySizes, contains('OEBPS/tOC.NCx'));
      expect(bookRef.knownEntrySizes,
          isNot(anyOf(contains('OEBPS/TOC.NCX'), contains('OEBPS/Toc.Ncx'))));
    });
  });

  group('readEntry', () {
    const String unlisted = 'OEBPS/images/bg.png';

    // TC-IDX-6 [Scenario]: an entry the manifest leaves out, an image only
    // the stylesheet points at, reads by its name. The first read finds it
    // by a pass over the directory; the second goes to it directly, so it
    // reads even once the directory no longer names it, where a book opened
    // afterwards finds nothing.
    test(
        'TC-IDX-6 [Scenario]: an entry the manifest leaves out is found once, '
        'then read directly', () async {
      final Uint8List zip = _book();
      final EpubBookRef bookRef =
          await _reader.openBook(zip, maxEntryBytes: null);

      expect(bookRef.knownEntrySizes, isNot(contains(unlisted)));
      expect(await bookRef.readEntry(unlisted), seedPngBytes());
      _rename(zip, unlisted, 'OEBPS/images/no.png');

      expect(await bookRef.readEntry(unlisted), seedPngBytes());
      expect(
          await (await _reader.openBook(zip, maxEntryBytes: null))
              .readEntry(unlisted),
          isNull);
      expect(bookRef.knownEntrySizes, isNot(contains(unlisted)));
    });

    // TC-IDX-7 [Scenario]: an entry opening kept is read directly, never
    // looked for in the directory, from the first read.
    test('TC-IDX-7 [Scenario]: a kept entry is read directly from the first',
        () async {
      final Uint8List zip = _book();
      final EpubBookRef bookRef =
          await _reader.openBook(zip, maxEntryBytes: null);
      _rename(zip, 'OEBPS/chapter1.xhtml', 'OEBPS/chapter9.xhtml');

      expect(await bookRef.readEntry('OEBPS/chapter1.xhtml'),
          utf8.encode(seedXhtml('NGE-SEED-INDEX-CH1')));
    });

    // TC-IDX-8 [Equivalence partitioning]: a name the archive does not hold
    // reads as null, by its full name only: a name relative to the package
    // document is not one, nor an escaped one. A name not found is not
    // remembered as missing: looked for again, it is found once the
    // directory holds it.
    test(
        'TC-IDX-8 [EP]: a name the archive does not hold reads as null, and '
        'is looked for again', () async {
      final Uint8List zip = _book();
      final EpubBookRef bookRef =
          await _reader.openBook(zip, maxEntryBytes: null);

      expect(await bookRef.readEntry('OEBPS/images/no.png'), isNull);
      expect(await bookRef.readEntry('images/bg.png'), isNull);
      expect(await bookRef.readEntry('OEBPS/Text/chapter%202.xhtml'), isNull);
      expect(await bookRef.readEntry(''), isNull);

      _rename(zip, unlisted, 'OEBPS/images/no.png');
      expect(await bookRef.readEntry('OEBPS/images/no.png'), seedPngBytes());
    });

    // TC-IDX-9 [Error guessing]: two records of one name, outside the
    // manifest. The later is the entry, as it is for a name opening keeps.
    test(
        'TC-IDX-9 [Error guessing]: of two records of one name, the later '
        'is read', () async {
      final Uint8List zip = _book(extra: <String, List<int>>{
        'extras/one.txt': utf8.encode('NGE-SEED-FIRST'),
        'extras/two.txt': utf8.encode('NGE-SEED-LATER'),
      });
      _rename(zip, 'extras/two.txt', 'extras/one.txt');
      final EpubBookRef bookRef =
          await _reader.openBook(zip, maxEntryBytes: null);

      expect(await bookRef.readEntry('extras/one.txt'),
          utf8.encode('NGE-SEED-LATER'));
    });

    // TC-IDX-10 [Boundary]: a read is held to the tighter of the book's
    // `maxEntryBytes` and the read's own `maxBytes`, whichever it is, for an
    // entry kept and one found alike. At the limit an entry reads; one byte
    // under it, it is refused. Each entry is 4 KiB, more than any document
    // opening parses, so the book opens under every limit here.
    const int size = 4096;
    final Map<String, String> entryByKind = <String, String>{
      'kept': 'OEBPS/big.bin',
      'found': 'extras/big.bin',
    };
    for (final MapEntry<String, String> entry in entryByKind.entries) {
      test(
          'TC-IDX-10 [Boundary]: a ${entry.key} entry is held to the tighter '
          'of maxEntryBytes and maxBytes', () async {
        final List<int> bytes = List<int>.generate(size, (int i) => i % 251);
        final Uint8List zip = _book(
          manifestExtra: '<item id="big" href="big.bin" '
              'media-type="application/octet-stream"/>',
          extra: <String, List<int>>{
            'OEBPS/big.bin': bytes,
            'extras/big.bin': bytes,
          },
        );
        Future<EpubBookRef> opened(int? limit) =>
            _reader.openBook(zip, maxEntryBytes: limit);

        for (final _Limits reads in const <_Limits>[
          _Limits(null, null),
          _Limits(null, size),
          _Limits(size, null),
          _Limits(size, size + 1),
          _Limits(size + 1, size),
          _Limits(size, 1 << 40),
        ]) {
          expect(
              await (await opened(reads.entry))
                  .readEntry(entry.value, maxBytes: reads.read),
              hasLength(size),
              reason: '$reads');
        }
        for (final _Limits reads in const <_Limits>[
          _Limits(null, size - 1),
          _Limits(size - 1, null),
          _Limits(size - 1, size + 1),
          _Limits(size + 1, size - 1),
          _Limits(null, 0),
        ]) {
          await expectLater(
              (await opened(reads.entry))
                  .readEntry(entry.value, maxBytes: reads.read),
              _throwsTooLarge,
              reason: '$reads');
        }
      });
    }

    // TC-IDX-11 [Scenario]: the limit stops the inflater part-way. An entry
    // the manifest leaves out, 8 MiB of zeros deflated to a few KiB, is
    // refused by a read held to 1 KiB as soon as its output passes that,
    // and reads whole with no limit.
    test('TC-IDX-11 [Scenario]: maxBytes stops a bomb part-way', () async {
      final Uint8List zip = _book(
          extra: <String, List<int>>{'extras/bomb.bin': Uint8List(8 << 20)});
      expect(zip.length, lessThan(64 * 1024));
      final EpubBookRef bookRef =
          await _reader.openBook(zip, maxEntryBytes: null);

      // Stopped by the inflater: what it had inflated by then, far short of
      // the 8 MiB a read checked only at its end would have reached.
      await expectLater(
          bookRef.readEntry('extras/bomb.bin', maxBytes: 1024),
          throwsA(isA<EpubArchiveTooLargeException>().having(
              (EpubArchiveTooLargeException e) => int.parse(
                  RegExp(r'^An entry inflates to at least (\d+) bytes; the '
                          r'read allows it at most 1024\.$')
                      .firstMatch(e.message)!
                      .group(1)!),
              'bytes inflated when stopped',
              inInclusiveRange(1025, 1024 + 64 * 1024))));
      expect(await bookRef.readEntry('extras/bomb.bin'), hasLength(8 << 20));
    });

    // TC-IDX-12 [Equivalence partitioning]: a `maxBytes` below zero is the
    // caller's mistake: an `ArgumentError`, whether the name is there or
    // not, and over an archive of the caller's as well. Zero is a limit.
    test('TC-IDX-12 [EP]: a maxBytes below zero is an argument error',
        () async {
      final EpubBookRef bookRef =
          await _reader.openBook(_book(), maxEntryBytes: null);
      final EpubBookRef built = EpubBookRef(
        epubArchive: Archive(),
        title: '',
        authorList: const <String>[],
        schema: bookRef.schema,
        content: bookRef.content,
      );

      for (final EpubBookRef ref in <EpubBookRef>[bookRef, built]) {
        await expectLater(ref.readEntry('OEBPS/style.css', maxBytes: -1),
            throwsArgumentError);
        await expectLater(
            ref.readEntry('NGE-SEED-none', maxBytes: -1), throwsArgumentError);
        expect(await ref.readEntry('NGE-SEED-none', maxBytes: 0), isNull);
      }
    });

    // TC-IDX-13 [Scenario]: a book file holds no handle, so an entry is
    // found and read by opening the file again. Once found, it is read
    // directly, even after the file's directory no longer names it.
    test(
        'TC-IDX-13 [Scenario]: an entry a book file leaves out of its '
        'manifest is found once, then read directly', () async {
      final Directory temp =
          Directory.systemTemp.createTempSync('nge_seed_index_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final File file = File('${temp.path}/book.epub');
      final Uint8List zip = _book();
      file.writeAsBytesSync(zip);
      final EpubBookRef bookRef =
          await _reader.openBookFile(file.path, maxEntryBytes: null);

      expect(await bookRef.readEntry(unlisted), seedPngBytes());
      _rename(zip, unlisted, 'OEBPS/images/no.png');
      file.writeAsBytesSync(zip);

      expect(await bookRef.readEntry(unlisted), seedPngBytes());
      expect(await bookRef.readEntry('OEBPS/images/no.png'), seedPngBytes());
    });
  });

  group('a book over an archive of the caller\'s', () {
    final Archive archive = Archive()
      ..addFile(ArchiveFile('a.bin', 3, Uint8List.fromList(<int>[1, 2, 3])))
      ..addFile(ArchiveFile('b.bin', 2, <int>[4, 5]));

    Future<EpubBookRef> built() async {
      final EpubBookRef opened =
          await _reader.openBook(_book(), maxEntryBytes: null);
      return EpubBookRef(
        epubArchive: archive,
        title: '',
        authorList: const <String>[],
        schema: opened.schema,
        content: opened.content,
      );
    }

    // TC-IDX-14 [Equivalence partitioning]: over an archive a caller built,
    // `readEntry` returns the bytes a file holds, or null, held to
    // `maxBytes` by their count, and `knownEntrySizes` lists every file.
    test(
        'TC-IDX-14 [EP]: readEntry and knownEntrySizes read an archive of '
        'the caller\'s', () async {
      final EpubBookRef bookRef = await built();

      expect(bookRef.knownEntrySizes, <String, int>{'a.bin': 3, 'b.bin': 2});
      expect(await bookRef.readEntry('a.bin'), <int>[1, 2, 3]);
      expect(await bookRef.readEntry('b.bin', maxBytes: 2), <int>[4, 5]);
      expect(await bookRef.readEntry('c.bin'), isNull);
      await expectLater(
          bookRef.readEntry('a.bin', maxBytes: 2),
          throwsA(isA<EpubArchiveTooLargeException>().having(
              (EpubArchiveTooLargeException e) => e.message,
              'message',
              'An entry holds 3 bytes; the read allows it at most 2.')));
    });
  });
}
