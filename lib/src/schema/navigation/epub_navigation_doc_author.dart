import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

class EpubNavigationDocAuthor {
  const EpubNavigationDocAuthor({required this.authors});

  /// The `<text>` children; empty when the `<docAuthor>` has none, although
  /// NCX requires one.
  final List<String> authors;

  @override
  int get hashCode =>
      hashObjects(authors.map((String author) => author.hashCode));

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationDocAuthor) {
      return false;
    }

    return collections.listsEqual(authors, other.authors);
  }
}
