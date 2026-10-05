import 'package:equatable/equatable.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';

class EpubNavigationTarget extends Equatable {
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
  List<Object?> get props =>
      <Object?>[id, className, value, playOrder, navigationLabels, content];
}
