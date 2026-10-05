import 'package:equatable/equatable.dart';

class EpubNavigationContent extends Equatable {
  const EpubNavigationContent({this.id, this.source});

  final String? id;

  /// Where the entry points. An NCX `<content>` requires `src`, and the
  /// reader refuses one without it; null for an EPUB 3 nav entry that is a
  /// heading (`<span>`, or `<a>` with no `href`) rather than a link, and for
  /// a page or nav target whose `<content>` is missing.
  final String? source;

  @override
  List<Object?> get props => <Object?>[id, source];

  @override
  String toString() {
    return 'Source: $source';
  }
}
