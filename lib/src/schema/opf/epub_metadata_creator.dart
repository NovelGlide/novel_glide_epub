import 'package:equatable/equatable.dart';

class EpubMetadataCreator extends Equatable {
  const EpubMetadataCreator({required this.creator, this.fileAs, this.role});

  /// The element's text; empty when the element is.
  final String creator;
  final String? fileAs;
  final String? role;

  @override
  List<Object?> get props => <Object?>[creator, fileAs, role];
}
