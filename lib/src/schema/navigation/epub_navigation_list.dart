import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_label.dart';
import 'epub_navigation_target.dart';

class EpubNavigationList {
  String? id;
  String? className;
  List<EpubNavigationLabel>? navigationLabels;
  List<EpubNavigationTarget>? navigationTargets;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      id.hashCode,
      className.hashCode,
      ...navigationLabels?.map((EpubNavigationLabel label) => label.hashCode) ??
          <int>[0],
      ...navigationTargets
              ?.map((EpubNavigationTarget target) => target.hashCode) ??
          <int>[0]
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
