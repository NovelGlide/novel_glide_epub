import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';
import 'epub_navigation_page_target_type.dart';

class EpubNavigationPageTarget {
  String? id;
  String? value;
  EpubNavigationPageTargetType? type;
  String? className;
  String? playOrder;
  List<EpubNavigationLabel>? navigationLabels;
  EpubNavigationContent? content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      id.hashCode,
      value.hashCode,
      type.hashCode,
      className.hashCode,
      playOrder.hashCode,
      content.hashCode,
      ...navigationLabels?.map((EpubNavigationLabel label) => label.hashCode) ??
          <int>[0]
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationPageTarget) {
      return false;
    }

    if (!(id == other.id &&
        value == other.value &&
        type == other.type &&
        className == other.className &&
        playOrder == other.playOrder &&
        content == other.content)) {
      return false;
    }

    return collections.listsEqual(navigationLabels, other.navigationLabels);
  }
}
