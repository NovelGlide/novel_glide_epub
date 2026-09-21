import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_label.dart';
import 'epub_navigation_target.dart';

class EpubNavigationList {
  String? Id;
  String? Class;
  List<EpubNavigationLabel>? NavigationLabels;
  List<EpubNavigationTarget>? NavigationTargets;

  @override
  int get hashCode {
    var objects = [
      Id.hashCode,
      Class.hashCode,
      ...NavigationLabels?.map((label) => label.hashCode) ?? [0],
      ...NavigationTargets?.map((target) => target.hashCode) ?? [0]
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationList) {
      return false;
    }

    if (!(Id == other.Id && Class == other.Class)) {
      return false;
    }

    if (!collections.listsEqual(NavigationLabels, other.NavigationLabels)) {
      return false;
    }
    if (!collections.listsEqual(NavigationTargets, other.NavigationTargets)) {
      return false;
    }
    return true;
  }
}
