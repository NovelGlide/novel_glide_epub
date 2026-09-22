import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';

class EpubNavigationPoint {
  String? id;
  String? className;
  String? playOrder;
  List<EpubNavigationLabel>? navigationLabels;
  EpubNavigationContent? content;
  List<EpubNavigationPoint>? childNavigationPoints;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      id.hashCode,
      className.hashCode,
      playOrder.hashCode,
      content.hashCode,
      ...navigationLabels!.map((EpubNavigationLabel label) => label.hashCode),
      ...childNavigationPoints!
          .map((EpubNavigationPoint point) => point.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationPoint) {
      return false;
    }

    if (!collections.listsEqual(navigationLabels, other.navigationLabels)) {
      return false;
    }

    if (!collections.listsEqual(
        childNavigationPoints, other.childNavigationPoints)) {
      return false;
    }

    return id == other.id &&
        className == other.className &&
        playOrder == other.playOrder &&
        content == other.content;
  }

  @override
  String toString() {
    return 'Id: $id, Content.Source: ${content!.source}';
  }
}
