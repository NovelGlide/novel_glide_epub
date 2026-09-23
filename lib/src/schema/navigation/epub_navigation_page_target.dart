import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';
import 'epub_navigation_page_target_type.dart';

class EpubNavigationPageTarget {
  const EpubNavigationPageTarget({
    required this.id,
    required this.type,
    required this.playOrder,
    required this.navigationLabels,
    required this.content,
    this.value,
    this.className,
  });

  /// Empty when the `<pageTarget>` has no `id`, although NCX requires one.
  final String id;
  final String? value;

  /// [EpubNavigationPageTargetType.undefined] when `type`, which NCX
  /// requires, is absent or names no NCX page type.
  final EpubNavigationPageTargetType type;
  final String? className;

  /// Empty when the `<pageTarget>` has no `playOrder`, although NCX requires
  /// one.
  final String playOrder;
  final List<EpubNavigationLabel> navigationLabels;

  /// A content with no source when the `<pageTarget>` has no `<content>`,
  /// although NCX requires one.
  final EpubNavigationContent content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      id.hashCode,
      value.hashCode,
      type.hashCode,
      className.hashCode,
      playOrder.hashCode,
      content.hashCode,
      ...navigationLabels.map((EpubNavigationLabel label) => label.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationPageTarget) {
      return false;
    }

    if (!(id == other.id &&
        value == other.value &&
        type == other.type &&
        className == other.className &&
        playOrder == other.playOrder &&
        content == other.content)) {
      return false;
    }

    return collections.listsEqual(navigationLabels, other.navigationLabels);
  }
}
