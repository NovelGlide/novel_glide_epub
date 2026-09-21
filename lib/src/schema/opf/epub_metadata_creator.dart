import 'package:quiver/core.dart';

class EpubMetadataCreator {
  String? Creator;
  String? FileAs;
  String? Role;

  @override
  int get hashCode => hash3(Creator.hashCode, FileAs.hashCode, Role.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataCreator) {
      return false;
    }
    return Creator == other.Creator &&
        FileAs == other.FileAs &&
        Role == other.Role;
  }
}
