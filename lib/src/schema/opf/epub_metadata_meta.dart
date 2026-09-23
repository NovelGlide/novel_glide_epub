import 'package:quiver/core.dart';

/// One `<meta>` of the package metadata, in either version's shape.
///
/// EPUB 2 and EPUB 3 give the element different attributes, so a field one
/// version requires is one the other never carries, and is nullable here.
class EpubMetadataMeta {
  const EpubMetadataMeta({
    required this.content,
    this.attributes = const <String, String>{},
    this.name,
    this.id,
    this.refines,
    this.property,
    this.scheme,
  });

  /// The EPUB 2 `name`. Null in an EPUB 3 book, whose reading systems must
  /// ignore the OPF 2 meta attributes, and in an EPUB 2 meta that omits it;
  /// [attributes] still holds it.
  final String? name;

  /// The EPUB 2 `content` attribute, or the EPUB 3 element text. Both
  /// versions require it; empty when the book leaves it out.
  final String content;
  final String? id;
  final String? refines;

  /// The EPUB 3 `property`. Null in EPUB 2, which has no such attribute, and
  /// in an EPUB 3 meta that omits it.
  final String? property;
  final String? scheme;

  /// Every attribute the element carries, keyed by lower-cased local name, so
  /// one this class has no field for is still readable.
  final Map<String, String> attributes;

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
