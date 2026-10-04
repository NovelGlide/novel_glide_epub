import 'package:equatable/equatable.dart';

class EpubNavigationDocAuthor extends Equatable {
  const EpubNavigationDocAuthor({required this.authors});

  /// The `<text>` children; empty when the `<docAuthor>` has none, although
  /// NCX requires one.
  final List<String> authors;

  @override
  List<Object?> get props => <Object?>[authors];
}
