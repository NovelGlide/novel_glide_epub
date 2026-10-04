import 'package:equatable/equatable.dart';

class EpubNavigationDocTitle extends Equatable {
  const EpubNavigationDocTitle({required this.titles});

  /// The `<text>` children; empty when the `<docTitle>` has none, although
  /// NCX requires one.
  final List<String> titles;

  @override
  List<Object?> get props => <Object?>[titles];
}
