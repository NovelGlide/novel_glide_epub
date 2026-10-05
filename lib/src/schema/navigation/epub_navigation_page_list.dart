import 'package:equatable/equatable.dart';

import 'epub_navigation_page_target.dart';

class EpubNavigationPageList extends Equatable {
  const EpubNavigationPageList({required this.targets});

  /// Empty when the `<pageList>` has no `<pageTarget>`, although NCX requires
  /// one.
  final List<EpubNavigationPageTarget> targets;

  @override
  List<Object?> get props => <Object?>[targets];
}
