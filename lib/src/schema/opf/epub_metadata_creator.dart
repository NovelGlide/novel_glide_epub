import 'package:quiver/core.dart';

class EpubMetadataCreator {
  String? creator;
  String? fileAs;
  String? role;

  @override
  int get hashCode => hash3(creator.hashCode, fileAs.hashCode, role.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataCreator) {
      return false;
    }
    return creator == other.creator &&
        fileAs == other.fileAs &&
        role == other.role;
  }
}
