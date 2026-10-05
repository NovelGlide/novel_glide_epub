import 'package:equatable/equatable.dart';

import 'epub_guide_reference.dart';

class EpubGuide extends Equatable {
  const EpubGuide({required this.items});

  /// Empty when the `<guide>` has no `<reference>`, although OPF 2 requires
  /// at least one: a guide pointing nowhere is no reason to refuse the book.
  final List<EpubGuideReference> items;

  @override
  List<Object?> get props => <Object?>[items];
}
