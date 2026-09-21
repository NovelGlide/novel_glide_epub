import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_page_target.dart';

class EpubNavigationPageList {
  List<EpubNavigationPageTarget>? Targets;

  @override
  int get hashCode {
    return hashObjects(Targets?.map((target) => target.hashCode) ?? [0]);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationPageList) {
      return false;
    }

    return collections.listsEqual(Targets, other.Targets);
  }
}
