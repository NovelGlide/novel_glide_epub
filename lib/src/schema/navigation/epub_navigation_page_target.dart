import 'package:equatable/equatable.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';
import 'epub_navigation_page_target_type.dart';

class EpubNavigationPageTarget extends Equatable {
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
  List<Object?> get props => <Object?>[
        id,
        value,
        type,
        className,
        playOrder,
        navigationLabels,
        content
      ];
}
