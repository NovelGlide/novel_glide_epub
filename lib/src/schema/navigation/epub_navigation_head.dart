import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_head_meta.dart';

class EpubNavigationHead {
  const EpubNavigationHead({required this.metadata});

  /// The `<meta>` children; empty when the `<head>` has none, although NCX
  /// requires at least one.
  final List<EpubNavigationHeadMeta> metadata;

  @override
  int get hashCode =>
      hashObjects(metadata.map((EpubNavigationHeadMeta meta) => meta.hashCode));

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationHead) {
      return false;
    }

    return collections.listsEqual(metadata, other.metadata);
  }
}
