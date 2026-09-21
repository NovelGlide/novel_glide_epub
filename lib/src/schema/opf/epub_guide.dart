import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_guide_reference.dart';

class EpubGuide {
  List<EpubGuideReference>? Items;

  EpubGuide() {
    Items = <EpubGuideReference>[];
  }

  @override
  int get hashCode {
    var objects = [];
    objects.addAll(Items!.map((item) => item.hashCode));
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubGuide) {
      return false;
    }

    return collections.listsEqual(Items, other.Items);
  }
}
