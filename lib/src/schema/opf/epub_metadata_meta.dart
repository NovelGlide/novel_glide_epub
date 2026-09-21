import 'package:quiver/core.dart';

class EpubMetadataMeta {
  String? Name;
  String? Content;
  String? Id;
  String? Refines;
  String? Property;
  String? Scheme;
  Map<String, String>? Attributes;

  @override
  int get hashCode => hashObjects([
        Name.hashCode,
        Content.hashCode,
        Id.hashCode,
        Refines.hashCode,
        Property.hashCode,
        Scheme.hashCode
      ]);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataMeta) {
      return false;
    }
    return Name == other.Name &&
        Content == other.Content &&
        Id == other.Id &&
        Refines == other.Refines &&
        Property == other.Property &&
        Scheme == other.Scheme;
  }
}
