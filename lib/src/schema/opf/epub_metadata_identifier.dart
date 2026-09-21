import 'package:quiver/core.dart';

class EpubMetadataIdentifier {
  String? Id;
  String? Scheme;
  String? Identifier;

  @override
  int get hashCode => hash3(Id.hashCode, Scheme.hashCode, Identifier.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataIdentifier) {
      return false;
    }
    return Id == other.Id &&
        Scheme == other.Scheme &&
        Identifier == other.Identifier;
  }
}
