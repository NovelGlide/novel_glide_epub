import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_page_target.dart';

class EpubNavigationPageList {
  const EpubNavigationPageList({required this.targets});

  /// Empty when the `<pageList>` has no `<pageTarget>`, although NCX requires
  /// one.
  final List<EpubNavigationPageTarget> targets;

  @override
  int get hashCode => hashObjects(
      targets.map((EpubNavigationPageTarget target) => target.hashCode));

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationPageList) {
      return false;
    }

    return collections.listsEqual(targets, other.targets);
  }
}
