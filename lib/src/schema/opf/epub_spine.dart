import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_spine_item_ref.dart';

class EpubSpine {
  String? tableOfContents;
  List<EpubSpineItemRef>? items;
  bool? ltr;

  @override
  int get hashCode {
    final List<int> objs = <int>[
      tableOfContents.hashCode,
      ltr.hashCode,
      ...items!.map((EpubSpineItemRef item) => item.hashCode)
    ];
    return hashObjects(objs);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubSpine) {
      return false;
    }

    if (!collections.listsEqual(items, other.items)) {
      return false;
    }
    return (tableOfContents == other.tableOfContents) && (ltr == other.ltr);
  }
}
