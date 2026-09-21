import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_spine_item_ref.dart';

class EpubSpine {
  String? TableOfContents;
  List<EpubSpineItemRef>? Items;
  bool? ltr;

  @override
  int get hashCode {
    final List<int> objs = <int>[
      TableOfContents.hashCode,
      ltr.hashCode,
      ...Items!.map((EpubSpineItemRef item) => item.hashCode)
    ];
    return hashObjects(objs);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubSpine) {
      return false;
    }

    if (!collections.listsEqual(Items, other.Items)) {
      return false;
    }
    return (TableOfContents == other.TableOfContents) && (ltr == other.ltr);
  }
}
