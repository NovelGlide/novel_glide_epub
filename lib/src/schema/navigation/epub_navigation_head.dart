import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_head_meta.dart';

class EpubNavigationHead {

  EpubNavigationHead() {
    Metadata = <EpubNavigationHeadMeta>[];
  }
  List<EpubNavigationHeadMeta>? Metadata;

  @override
  int get hashCode {
    final List<int> objects = <int>[...Metadata!.map((EpubNavigationHeadMeta meta) => meta.hashCode)];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationHead) {
      return false;
    }

    return collections.listsEqual(Metadata, other.Metadata);
  }
}
