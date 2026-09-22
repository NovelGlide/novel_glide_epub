import 'package:quiver/core.dart';

class EpubMetadataMeta {
  String? name;
  String? content;
  String? id;
  String? refines;
  String? property;
  String? scheme;
  Map<String, String>? attributes;

  @override
  int get hashCode => hashObjects(<Object?>[
        name.hashCode,
        content.hashCode,
        id.hashCode,
        refines.hashCode,
        property.hashCode,
        scheme.hashCode
      ]);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataMeta) {
      return false;
    }
    return name == other.name &&
        content == other.content &&
        id == other.id &&
        refines == other.refines &&
        property == other.property &&
        scheme == other.scheme;
  }
}
