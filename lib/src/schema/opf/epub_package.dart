import 'package:quiver/core.dart';

import 'epub_guide.dart';
import 'epub_manifest.dart';
import 'epub_metadata.dart';
import 'epub_spine.dart';
import 'epub_version.dart';

class EpubPackage {
  const EpubPackage({
    required this.version,
    required this.metadata,
    required this.manifest,
    required this.spine,
    this.guide,
  });

  final EpubVersion version;
  final EpubMetadata metadata;
  final EpubManifest manifest;
  final EpubSpine spine;

  /// Null when the package has no `<guide>`: OPF 2 makes the element
  /// optional, and EPUB 3 deprecates it.
  final EpubGuide? guide;

  @override
  int get hashCode => hashObjects(<Object?>[
        version.hashCode,
        metadata.hashCode,
        manifest.hashCode,
        spine.hashCode,
        guide.hashCode
      ]);

  @override
  bool operator ==(Object other) {
    if (other is! EpubPackage) {
      return false;
    }

    return version == other.version &&
        metadata == other.metadata &&
        manifest == other.manifest &&
        spine == other.spine &&
        guide == other.guide;
  }
}
