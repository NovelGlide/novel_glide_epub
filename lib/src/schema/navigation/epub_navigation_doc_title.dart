import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

class EpubNavigationDocTitle {
  const EpubNavigationDocTitle({required this.titles});

  /// The `<text>` children; empty when the `<docTitle>` has none, although
  /// NCX requires one.
  final List<String> titles;

  @override
  int get hashCode => hashObjects(titles.map((String title) => title.hashCode));

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationDocTitle) {
      return false;
    }

    return collections.listsEqual(titles, other.titles);
  }
}
