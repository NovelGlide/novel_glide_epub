// The package's own dependency list, read from the files a consumer resolves.
//
// Equality is decided by `package:equatable` alone, so `package:quiver`,
// which used to supply the hand-written `==` and `hashCode` helpers, is no
// longer a dependency. A consumer that reached quiver only through this
// package has to declare it itself.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Dependencies', () {
    // TC-DEP-1 [Scenario/use-case]: quiver is neither declared in
    // `pubspec.yaml` nor imported anywhere under `lib/`.
    test('TC-DEP-1 [Scenario]: quiver is not a dependency', () {
      final List<String> pubspec = File('pubspec.yaml').readAsLinesSync();
      final List<String> libSources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File file) => file.path.endsWith('.dart'))
          .map((File file) => file.readAsStringSync())
          .toList();

      expect(pubspec, contains('  equatable: \'>=2.0.5 <4.0.0\''));
      expect(
        pubspec.where((String line) => line.trimLeft().startsWith('quiver:')),
        isEmpty,
      );
      expect(libSources, isNotEmpty);
      expect(
        libSources.where((String source) => source.contains('package:quiver')),
        isEmpty,
      );
    });
  });
}
