import 'package:quiver/core.dart';

class EpubGuideReference {
  String? Type;
  String? Title;
  String? Href;

  @override
  int get hashCode => hash3(Type.hashCode, Title.hashCode, Href.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubGuideReference) {
      return false;
    }

    return Type == other.Type && Title == other.Title && Href == other.Href;
  }

  @override
  String toString() {
    return 'Type: $Type, Href: $Href';
  }
}
