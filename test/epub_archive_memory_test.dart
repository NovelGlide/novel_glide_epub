// What opening a book and reading its entries cost in memory, measured in a
// process of its own (`support/archive_memory_probe.dart`): the peak memory
// a process has reached cannot be reset, so a measurement made alongside
// other tests would read whatever they left behind. The probe is compiled
// ahead of time because a process running from source has already peaked
// at well over a hundred MiB compiling itself, which would hide most of
// what it measures. Each case runs the probe twice in one scratch directory
// and takes the second run's figure: the first builds the fixture, which
// for a large one raises the peak before the call it is about.
//
// Each case opens or reads more data than its bound allows twice over, so a
// regression to holding the data shows as a peak of the data's size. The
// reads are of books opened with a 256 MiB limit on one entry unless a case
// says otherwise.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory scratch;
  late String probe;

  setUpAll(() async {
    scratch = Directory.systemTemp.createTempSync('nge_seed_memory_');
    probe = '${scratch.path}/probe';
    final ProcessResult compiled = await Process.run(
      Platform.resolvedExecutable,
      <String>[
        'compile',
        'exe',
        'test/support/archive_memory_probe.dart',
        '-o',
        probe,
      ],
    );
    expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
  });

  tearDownAll(() {
    scratch.deleteSync(recursive: true);
  });

  /// How many MiB the probe's peak memory grew by across the call
  /// [probeCase] is about, in a run whose fixture an earlier one built.
  Future<int> peakGrowthMib(String probeCase) async {
    final Directory work = scratch.createTempSync('case');
    late ProcessResult result;
    for (int run = 0; run < 2; run++) {
      result = await Process.run(probe, <String>[probeCase, work.path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    work.deleteSync(recursive: true);
    return int.parse((result.stdout as String).trim());
  }

  // TC-MEM-1 [Scenario]: `openBookFile` reads a file's directory, never the
  // file whole and no entry it does not parse. A file
  // with a 128 MiB stored entry is opened without it being held.
  test(
      'TC-MEM-1 [Scenario]: opening a file with a 128 MiB entry does not '
      'hold it', () async {
    expect(await peakGrowthMib('file'), lessThan(32));
  });

  // TC-MEM-6 [Scenario]: nothing about a file's size is held when it is
  // opened. A book after a 1.5 GiB hole, a sparse file, opens as a small
  // one does.
  test('TC-MEM-6 [Scenario]: opening a 1.5 GiB file does not hold it',
      () async {
    expect(await peakGrowthMib('large'), lessThan(32));
  });

  // TC-MEM-7 [Scenario]: what opening holds for the central directory grows
  // with the book's `META-INF/` entries and its manifest, not with the
  // records the directory has. A book with 100,000 one-byte entries its
  // manifest does not list, 11 MiB of file, may grow the peak by 16 MiB,
  // measured at 3; holding a record for each, about half a KiB apiece, took
  // it to 52.
  test(
      'TC-MEM-7 [Scenario]: opening a book with 100,000 entries it does not '
      'list holds none of them', () async {
    expect(await peakGrowthMib('entries:100000'), lessThan(16));
  });

  // TC-MEM-9 [Scenario]: a file of nothing but records holds nothing for
  // them. A directory record takes 46 bytes and a name, and records storing
  // nothing pass the overlap check, so 100,000 of them take 4.9 MiB of file.
  // Opening it reads every record, keeps none, and fails on the container
  // it does not have; the peak may grow by 16 MiB, measured at 3.
  test(
      'TC-MEM-9 [Scenario]: opening a file of nothing but 100,000 records '
      'holds none of them', () async {
    expect(await peakGrowthMib('records:100000'), lessThan(16));
  });

  // TC-MEM-11 [Scenario]: what opening a readable book holds stays flat
  // however many records its directory has besides its own. 4,096, 100,000
  // and 1,000,000 zero-length records the manifest does not list, up to
  // 50 MiB of directory, may each grow the peak by 16 MiB, all measured at
  // 2 to 3; holding a record for each took the last two to 53 and 281.
  for (final int records in <int>[4096, 100000, 1000000]) {
    test(
        'TC-MEM-11 [Scenario]: opening a book with $records more records '
        'holds none of them', () async {
      expect(await peakGrowthMib('book-records:$records'), lessThan(16));
    }, timeout: const Timeout(Duration(minutes: 2)));
  }

  // TC-MEM-4 [Scenario]: opening reads no entry's local header. 4096
  // records sharing one whose name and extra field are 64 KiB each take a
  // third of a MiB of file, and may grow the peak by 32 MiB. Parsed for
  // each record, with each parse kept, that header would take it past
  // 300 MiB.
  test(
      'TC-MEM-4 [Scenario]: opening 4096 records that share one 128 KiB '
      'local header does not parse it', () async {
    expect(await peakGrowthMib('shared'), lessThan(32));
  });

  // TC-MEM-2 [Scenario]: a bomb read is stopped at the limit the caller
  // passed. An entry declaring 1 KiB and inflating to 1 GiB, or to 4 GiB,
  // may grow the peak by 300 MiB: what it inflated to by the time it
  // crossed the 256 MiB limit, and a sixth again for the chunks in flight
  // and the allocator's slack. An inflater that did not stop would reach
  // the bomb's size; one that grew its buffer by doubling, 512 MiB.
  for (final String bomb in <String>['bomb', 'bomb4g']) {
    test('TC-MEM-2 [Scenario]: reading a bomb ($bomb) is stopped at the limit',
        () async {
      expect(await peakGrowthMib(bomb), lessThan(300));
    });
  }

  // TC-MEM-3 [Scenario]: reading a content file as bytes holds it once. A
  // 200 MiB stored entry, read through `readContentAsBytes` after the book
  // is opened, may grow the peak by 250 MiB: the entry itself, and a
  // quarter again for the reading chunks and the allocator's slack. A second
  // copy of the entry would take it to 400 at least.
  test(
      'TC-MEM-3 [Scenario]: reading a 200 MiB content file as bytes holds '
      'it once', () async {
    expect(await peakGrowthMib('read'), lessThan(250));
  });

  // TC-MEM-8 [Scenario]: read with no limit, an honest entry is still held
  // once. Its buffer is made for the size it declares, as far as its stored
  // bytes can fill it: a 200 MiB stored entry may grow the peak by 250 MiB,
  // as TC-MEM-3's does under a limit. Collected a chunk at a time and joined
  // at the end, it would be held twice, past 400.
  test(
      'TC-MEM-8 [Scenario]: reading a 200 MiB content file with no limit '
      'holds it once', () async {
    expect(await peakGrowthMib('read-unlimited'), lessThan(250));
  });

  // TC-MEM-10 [Scenario]: the same for a deflated entry, whose buffer is
  // bounded by the most its compressed bytes can inflate to. 200 MiB of
  // deflated zeros, declaring their size, read with no limit, may grow the
  // peak by 250 MiB; a buffer bounded by less than they inflate to would be
  // outgrown and joined, past 400.
  test(
      'TC-MEM-10 [Scenario]: reading a 200 MiB deflated content file with no '
      'limit holds it once', () async {
    expect(await peakGrowthMib('read-deflated-unlimited'), lessThan(250));
  });

  // TC-MEM-5 [Scenario]: reads through one `EpubBookRef` do not add up. A
  // 200 MiB stored entry read as bytes five times in a row, each read's
  // bytes dropped before the next, may grow the peak by 450 MiB: about two
  // entries and slack, however many reads there are. Why two and not one is
  // inferred, not measured: the read before is likely not yet collected
  // when the next allocates its buffer. Were every read kept, the five would
  // take it past 1000. Memory cannot tell one read kept from none;
  // `epub_ref_retention_test.dart` asks the collector that.
  test(
      'TC-MEM-5 [Scenario]: reading a 200 MiB content file five times from '
      'one ref does not add the reads up', () async {
    expect(await peakGrowthMib('reread'), lessThan(450));
  });
}
