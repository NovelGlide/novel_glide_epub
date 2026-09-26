// What opening a book costs in memory, measured in a process of its own
// (`support/archive_memory_probe.dart`): the peak memory a process has
// reached cannot be reset, so a measurement made alongside other tests would
// read whatever they left behind. The probe is compiled ahead of time
// because a process running from source has already peaked at well over a
// hundred MiB compiling itself, which would hide most of what it measures.
//
// Each case opens a container with far more data in it than its bound, so a
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

  // TC-MEM-1 [Scenario]: `openBookFile` reads a file a chunk at a time. A
  // 128 MiB stored entry is read, and counted, without the file or the entry
  // being held.
  test(
      'TC-MEM-1 [Scenario]: opening a file with a 128 MiB entry does not '
      'hold it', () async {
    expect(await peakGrowthMib('file'), lessThan(32));
  });

  // TC-MEM-2 [Scenario]: validation inflates every entry and keeps none of
  // it. An entry inflating to the 256 MiB limit is validated in chunks.
  test(
      'TC-MEM-2 [Scenario]: validating an entry that inflates to 256 MiB '
      'does not hold it', () async {
    expect(await peakGrowthMib('inflate'), lessThan(32));
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
