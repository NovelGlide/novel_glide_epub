import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';

class EpubNavigationPoint {
  String? Id;
  String? Class;
  String? PlayOrder;
  List<EpubNavigationLabel>? NavigationLabels;
  EpubNavigationContent? Content;
  List<EpubNavigationPoint>? ChildNavigationPoints;

  @override
  int get hashCode {
    var objects = [
      Id.hashCode,
      Class.hashCode,
      PlayOrder.hashCode,
      Content.hashCode,
      ...NavigationLabels!.map((label) => label.hashCode),
      ...ChildNavigationPoints!.map((point) => point.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationPoint) {
      return false;
    }

    if (!collections.listsEqual(NavigationLabels, other.NavigationLabels)) {
      return false;
    }

    if (!collections.listsEqual(
        ChildNavigationPoints, other.ChildNavigationPoints)) {
      return false;
    }

    return Id == other.Id &&
        Class == other.Class &&
        PlayOrder == other.PlayOrder &&
        Content == other.Content;
  }

  @override
  String toString() {
    return 'Id: $Id, Content.Source: ${Content!.Source}';
  }
}
