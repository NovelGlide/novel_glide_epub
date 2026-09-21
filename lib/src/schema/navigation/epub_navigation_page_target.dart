import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';
import 'epub_navigation_page_target_type.dart';

class EpubNavigationPageTarget {
  String? Id;
  String? Value;
  EpubNavigationPageTargetType? Type;
  String? Class;
  String? PlayOrder;
  List<EpubNavigationLabel>? NavigationLabels;
  EpubNavigationContent? Content;

  @override
  int get hashCode {
    var objects = [
      Id.hashCode,
      Value.hashCode,
      Type.hashCode,
      Class.hashCode,
      PlayOrder.hashCode,
      Content.hashCode,
      ...NavigationLabels?.map((label) => label.hashCode) ?? [0]
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationPageTarget) {
      return false;
    }

    if (!(Id == other.Id &&
        Value == other.Value &&
        Type == other.Type &&
        Class == other.Class &&
        PlayOrder == other.PlayOrder &&
        Content == other.Content)) {
      return false;
    }

    return collections.listsEqual(NavigationLabels, other.NavigationLabels);
  }
}
