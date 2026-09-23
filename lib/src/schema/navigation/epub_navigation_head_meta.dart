import 'package:quiver/core.dart';

class EpubNavigationHeadMeta {
  const EpubNavigationHeadMeta(
      {required this.name, required this.content, this.scheme});

  final String name;
  final String content;
  final String? scheme;

  @override
  int get hashCode => hash3(name.hashCode, content.hashCode, scheme.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationHeadMeta) {
      return false;
    }

    return name == other.name &&
        content == other.content &&
        scheme == other.scheme;
  }
}
