import 'package:quiver/core.dart';

class EpubNavigationHeadMeta {
  String? Name;
  String? Content;
  String? Scheme;

  @override
  int get hashCode => hash3(Name.hashCode, Content.hashCode, Scheme.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationHeadMeta) {
      return false;
    }

    return Name == other.Name &&
        Content == other.Content &&
        Scheme == other.Scheme;
  }
}
