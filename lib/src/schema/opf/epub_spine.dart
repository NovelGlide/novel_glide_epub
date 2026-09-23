import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_spine_item_ref.dart';

class EpubSpine {
  const EpubSpine({
    required this.items,
    required this.ltr,
    this.tableOfContents,
  });

  /// The manifest id of the NCX. Null when the spine has no `toc`: EPUB 2
  /// requires the attribute, but EPUB 3 makes it optional, and the EPUB 2
  /// navigation reader refuses a book without it where it needs it.
  final String? tableOfContents;

  /// Empty when the `<spine>` has no `<itemref>`, although OPF requires at
  /// least one.
  final List<EpubSpineItemRef> items;

  /// True when `page-progression-direction` is absent or `ltr`; `rtl` and
  /// `default` both read as false.
  final bool ltr;

  @override
  int get hashCode {
    final List<int> objs = <int>[
      tableOfContents.hashCode,
      ltr.hashCode,
      ...items.map((EpubSpineItemRef item) => item.hashCode)
    ];
    return hashObjects(objs);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubSpine) {
      return false;
    }

    if (!collections.listsEqual(items, other.items)) {
      return false;
    }
    return (tableOfContents == other.tableOfContents) && (ltr == other.ltr);
  }
}
