import 'package:quiver/core.dart';

class EpubMetadataContributor {
  const EpubMetadataContributor(
      {required this.contributor, this.fileAs, this.role});

  /// The element's text; empty when the element is.
  final String contributor;
  final String? fileAs;
  final String? role;

  @override
  int get hashCode =>
      hash3(contributor.hashCode, fileAs.hashCode, role.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataContributor) {
      return false;
    }

    return contributor == other.contributor &&
        fileAs == other.fileAs &&
        role == other.role;
  }
}
