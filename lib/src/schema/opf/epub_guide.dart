import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_guide_reference.dart';

class EpubGuide {

  EpubGuide() {
    Items = <EpubGuideReference>[];
  }
  List<EpubGuideReference>? Items;

  @override
  int get hashCode {
    final List<dynamic> objects = <dynamic>[];
    objects.addAll(Items!.map((EpubGuideReference item) => item.hashCode));
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
