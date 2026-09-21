import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

class EpubNavigationDocTitle {

  EpubNavigationDocTitle() {
    Titles = <String>[];
  }
  List<String>? Titles;

  @override
  int get hashCode {
    final List<int> objects = <int>[...Titles!.map((String title) => title.hashCode)];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationDocTitle) {
      return false;
    }

    return collections.listsEqual(Titles, other.Titles);
  }
}
