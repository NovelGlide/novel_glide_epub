import 'package:quiver/core.dart';

class EpubMetadataCreator {
  const EpubMetadataCreator({required this.creator, this.fileAs, this.role});

  /// The element's text; empty when the element is.
  final String creator;
  final String? fileAs;
  final String? role;

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
