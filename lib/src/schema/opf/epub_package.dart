import 'package:quiver/core.dart';

import 'epub_guide.dart';
import 'epub_manifest.dart';
import 'epub_metadata.dart';
import 'epub_spine.dart';
import 'epub_version.dart';

class EpubPackage {
  EpubVersion? Version;
  EpubMetadata? Metadata;
  EpubManifest? Manifest;
  EpubSpine? Spine;
  EpubGuide? Guide;

  @override
  int get hashCode => hashObjects([
        Version.hashCode,
        Metadata.hashCode,
        Manifest.hashCode,
        Spine.hashCode,
        Guide.hashCode
      ]);

  @override
  bool operator ==(Object other) {
    if (other is! EpubPackage) {
      return false;
    }

    return Version == other.Version &&
        Metadata == other.Metadata &&
        Manifest == other.Manifest &&
        Spine == other.Spine &&
        Guide == other.Guide;
  }
}
