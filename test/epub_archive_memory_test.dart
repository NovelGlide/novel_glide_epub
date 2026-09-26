// What opening a book and reading its entries cost in memory, measured in a
// process of its own (`support/archive_memory_probe.dart`): the peak memory
// a process has reached cannot be reset, so a measurement made alongside
// other tests would read whatever they left behind. The probe is compiled
// ahead of time because a process running from source has already peaked
// at well over a hundred MiB compiling itself, which would hide most of
// what it measures.
//
// Each case opens or reads more data than its bound allows twice over, so a
// regression to holding the data shows as a peak of the data's size.
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
  /// [probeCase] is about.
  Future<int> peakGrowthMib(String probeCase) async {
    final Directory work = scratch.createTempSync(probeCase);
    final ProcessResult result =
        await Process.run(probe, <String>[probeCase, work.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
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

  // TC-MEM-2 [Scenario]: a bomb read is stopped at the per-entry limit. An
  // entry declaring 1 KiB and inflating to 1 GiB may grow the peak by
  // 300 MiB: what it inflated to by the time it crossed the 256 MiB limit,
  // and a sixth again for the chunks in flight and the allocator's slack.
  // An inflater that did not stop would reach the gigabyte; one that grew
  // its buffer by doubling, 512 MiB.
  test('TC-MEM-2 [Scenario]: reading a 1 GiB bomb is stopped at the limit',
      () async {
    expect(await peakGrowthMib('bomb'), lessThan(300));
  });

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
}
