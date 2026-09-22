import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';

class EpubNavigationTarget {
  String? id;
  String? className;
  String? value;
  String? playOrder;
  List<EpubNavigationLabel>? navigationLabels;
  EpubNavigationContent? content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      id.hashCode,
      className.hashCode,
      value.hashCode,
      playOrder.hashCode,
      content.hashCode,
      ...navigationLabels!.map((EpubNavigationLabel label) => label.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationTarget) {
      return false;
    }

    if (!(id == other.id &&
        className == other.className &&
        value == other.value &&
        playOrder == other.playOrder &&
        content == other.content)) {
      return false;
    }

    return collections.listsEqual(navigationLabels, other.navigationLabels);
  }
}
