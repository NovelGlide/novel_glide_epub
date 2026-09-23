import 'package:quiver/core.dart';

class EpubGuideReference {
  const EpubGuideReference({
    required this.type,
    required this.href,
    this.title,
  });

  final String type;
  final String href;

  /// Null when the reference has no `title`, which OPF 2 makes optional.
  final String? title;

  @override
  int get hashCode => hash3(type.hashCode, title.hashCode, href.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubGuideReference) {
      return false;
    }

    return type == other.type && title == other.title && href == other.href;
  }

  @override
  String toString() {
    return 'Type: $type, Href: $href';
  }
}
