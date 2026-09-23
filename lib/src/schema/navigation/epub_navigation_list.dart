import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_label.dart';
import 'epub_navigation_target.dart';

class EpubNavigationList {
  const EpubNavigationList({
    required this.navigationLabels,
    required this.navigationTargets,
    this.id,
    this.className,
  });

  final String? id;
  final String? className;

  /// Empty when the `<navList>` has no `<navLabel>`, although NCX requires
  /// one.
  final List<EpubNavigationLabel> navigationLabels;

  /// Empty when the `<navList>` has no `<navTarget>`, although NCX requires
  /// one.
  final List<EpubNavigationTarget> navigationTargets;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      id.hashCode,
      className.hashCode,
      ...navigationLabels.map((EpubNavigationLabel label) => label.hashCode),
      ...navigationTargets.map((EpubNavigationTarget target) => target.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationList) {
      return false;
    }

    if (!(id == other.id && className == other.className)) {
      return false;
    }

    if (!collections.listsEqual(navigationLabels, other.navigationLabels)) {
      return false;
    }
    if (!collections.listsEqual(navigationTargets, other.navigationTargets)) {
      return false;
    }
    return true;
  }
}
