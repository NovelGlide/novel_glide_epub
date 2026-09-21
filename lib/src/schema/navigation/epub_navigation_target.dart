import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';

class EpubNavigationTarget {
  String? Id;
  String? Class;
  String? Value;
  String? PlayOrder;
  List<EpubNavigationLabel>? NavigationLabels;
  EpubNavigationContent? Content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      Id.hashCode,
      Class.hashCode,
      Value.hashCode,
      PlayOrder.hashCode,
      Content.hashCode,
      ...NavigationLabels!.map((EpubNavigationLabel label) => label.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationTarget) {
      return false;
    }

    if (!(Id == other.Id &&
        Class == other.Class &&
        Value == other.Value &&
        PlayOrder == other.PlayOrder &&
        Content == other.Content)) {
      return false;
    }

    return collections.listsEqual(NavigationLabels, other.NavigationLabels);
  }
}
