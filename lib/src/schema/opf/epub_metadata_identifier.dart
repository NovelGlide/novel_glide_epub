import 'package:equatable/equatable.dart';

class EpubMetadataIdentifier extends Equatable {
  const EpubMetadataIdentifier(
      {required this.identifier, this.id, this.scheme});

  final String? id;
  final String? scheme;

  /// The element's text; empty when the element is.
  final String identifier;

  @override
  List<Object?> get props => <Object?>[id, scheme, identifier];
}
