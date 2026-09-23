import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_manifest_item.dart';

class EpubManifest {
  const EpubManifest({required this.items});

  /// Empty when the `<manifest>` has no `<item>`, although OPF requires at
  /// least one.
  final List<EpubManifestItem> items;

  @override
  int get hashCode =>
      hashObjects(items.map((EpubManifestItem item) => item.hashCode));

  @override
  bool operator ==(Object other) {
    if (other is! EpubManifest) {
      return false;
    }
    return collections.listsEqual(items, other.items);
  }
}
