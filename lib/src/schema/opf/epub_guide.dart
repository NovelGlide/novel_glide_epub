import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_guide_reference.dart';

class EpubGuide {
  const EpubGuide({required this.items});

  /// Empty when the `<guide>` has no `<reference>`, although OPF 2 requires
  /// at least one: a guide pointing nowhere is no reason to refuse the book.
  final List<EpubGuideReference> items;

  @override
  int get hashCode =>
      hashObjects(items.map((EpubGuideReference item) => item.hashCode));

  @override
  bool operator ==(Object other) {
    if (other is! EpubGuide) {
      return false;
    }

    return collections.listsEqual(items, other.items);
  }
}
