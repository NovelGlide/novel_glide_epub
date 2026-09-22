import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_head_meta.dart';

class EpubNavigationHead {
  EpubNavigationHead() {
    metadata = <EpubNavigationHeadMeta>[];
  }
  List<EpubNavigationHeadMeta>? metadata;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      ...metadata!.map((EpubNavigationHeadMeta meta) => meta.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationHead) {
      return false;
    }

    return collections.listsEqual(metadata, other.metadata);
  }
}
