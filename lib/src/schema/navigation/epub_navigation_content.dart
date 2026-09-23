import 'package:quiver/core.dart';

class EpubNavigationContent {
  const EpubNavigationContent({this.id, this.source});

  final String? id;

  /// Where the entry points. An NCX `<content>` requires `src`, and the
  /// reader refuses one without it; null for an EPUB 3 nav entry that is a
  /// heading (`<span>`, or `<a>` with no `href`) rather than a link, and for
  /// a page or nav target whose `<content>` is missing.
  final String? source;

  @override
  int get hashCode => hash2(id.hashCode, source.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationContent) {
      return false;
    }
    return id == other.id && source == other.source;
  }

  @override
  String toString() {
    return 'Source: $source';
  }
}
