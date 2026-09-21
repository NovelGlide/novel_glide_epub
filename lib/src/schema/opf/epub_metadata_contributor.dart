import 'package:quiver/core.dart';

class EpubMetadataContributor {
  String? Contributor;
  String? FileAs;
  String? Role;

  @override
  int get hashCode =>
      hash3(Contributor.hashCode, FileAs.hashCode, Role.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataContributor) {
      return false;
    }

    return Contributor == other.Contributor &&
        FileAs == other.FileAs &&
        Role == other.Role;
  }
}
