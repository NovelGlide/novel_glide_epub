import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

class EpubNavigationDocAuthor {

  EpubNavigationDocAuthor() {
    Authors = <String>[];
  }
  List<String>? Authors;

  @override
  int get hashCode {
    final List<int> objects = <int>[...Authors!.map((String author) => author.hashCode)];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationDocAuthor) {
      return false;
    }

    return collections.listsEqual(Authors, other.Authors);
  }
}
