import 'package:equatable/equatable.dart';

import 'epub_navigation_head_meta.dart';

class EpubNavigationHead extends Equatable {
  const EpubNavigationHead({required this.metadata});

  /// The `<meta>` children; empty when the `<head>` has none, although NCX
  /// requires at least one.
  final List<EpubNavigationHeadMeta> metadata;

  @override
  List<Object?> get props => <Object?>[metadata];
}
