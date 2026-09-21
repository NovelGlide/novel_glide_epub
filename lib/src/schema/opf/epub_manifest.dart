import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_manifest_item.dart';

class EpubManifest {

  EpubManifest() {
    Items = <EpubManifestItem>[];
  }
  List<EpubManifestItem>? Items;

  @override
  int get hashCode {
    return hashObjects(Items!.map((EpubManifestItem item) => item.hashCode));
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubManifest) {
      return false;
    }
    return collections.listsEqual(Items, other.Items);
  }
}
