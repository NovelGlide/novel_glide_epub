import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';

class EpubNavigationTarget {
  const EpubNavigationTarget({
    required this.id,
    required this.playOrder,
    required this.navigationLabels,
    required this.content,
    this.className,
    this.value,
  });

  final String id;
  final String? className;
  final String? value;

  /// Empty when the `<navTarget>` has no `playOrder`, although NCX requires
  /// one.
  final String playOrder;
  final List<EpubNavigationLabel> navigationLabels;

  /// A content with no source when the `<navTarget>` has no `<content>`,
  /// although NCX requires one.
  final EpubNavigationContent content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      id.hashCode,
      className.hashCode,
      value.hashCode,
      playOrder.hashCode,
      content.hashCode,
      ...navigationLabels.map((EpubNavigationLabel label) => label.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationTarget) {
      return false;
    }

    if (!(id == other.id &&
        className == other.className &&
        value == other.value &&
        playOrder == other.playOrder &&
        content == other.content)) {
      return false;
    }

    return collections.listsEqual(navigationLabels, other.navigationLabels);
  }
}
