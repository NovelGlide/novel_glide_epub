import 'package:quiver/core.dart';

class EpubMetadataIdentifier {
  const EpubMetadataIdentifier(
      {required this.identifier, this.id, this.scheme});

  final String? id;
  final String? scheme;

  /// The element's text; empty when the element is.
  final String identifier;

  @override
  int get hashCode => hash3(id.hashCode, scheme.hashCode, identifier.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataIdentifier) {
      return false;
    }
    return id == other.id &&
        scheme == other.scheme &&
        identifier == other.identifier;
  }
}
