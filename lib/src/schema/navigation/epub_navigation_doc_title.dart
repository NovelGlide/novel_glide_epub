import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

class EpubNavigationDocTitle {
  EpubNavigationDocTitle() {
    titles = <String>[];
  }
  List<String>? titles;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      ...titles!.map((String title) => title.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationDocTitle) {
      return false;
    }

    return collections.listsEqual(titles, other.titles);
  }
}
