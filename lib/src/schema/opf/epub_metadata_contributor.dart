import 'package:equatable/equatable.dart';

class EpubMetadataContributor extends Equatable {
  const EpubMetadataContributor(
      {required this.contributor, this.fileAs, this.role});

  /// The element's text; empty when the element is.
  final String contributor;
  final String? fileAs;
  final String? role;

  @override
  List<Object?> get props => <Object?>[contributor, fileAs, role];
}
