import 'package:equatable/equatable.dart';

import 'epub_navigation_label.dart';
import 'epub_navigation_target.dart';

class EpubNavigationList extends Equatable {
  const EpubNavigationList({
    required this.navigationLabels,
    required this.navigationTargets,
    this.id,
    this.className,
  });

  final String? id;
  final String? className;

  /// Empty when the `<navList>` has no `<navLabel>`, although NCX requires
  /// one.
  final List<EpubNavigationLabel> navigationLabels;

  /// Empty when the `<navList>` has no `<navTarget>`, although NCX requires
  /// one.
  final List<EpubNavigationTarget> navigationTargets;

  @override
  List<Object?> get props =>
      <Object?>[id, className, navigationLabels, navigationTargets];
}
