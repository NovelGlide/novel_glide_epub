import 'package:quiver/core.dart';

class EpubMetadataIdentifier {
  String? id;
  String? scheme;
  String? identifier;

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
