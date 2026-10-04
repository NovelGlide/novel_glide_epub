import 'package:equatable/equatable.dart';

import 'epub_navigation_content.dart';
import 'epub_navigation_label.dart';

class EpubNavigationPoint extends Equatable {
  const EpubNavigationPoint({
    required this.id,
    required this.playOrder,
    required this.navigationLabels,
    required this.content,
    this.className,
    this.childNavigationPoints = const <EpubNavigationPoint>[],
  });

  /// Empty for an EPUB 3 nav entry, which has no NCX id.
  final String id;
  final String? className;

  /// Empty when the `<navPoint>` has no `playOrder`, although NCX requires
  /// one, and for an EPUB 3 nav entry, which has none.
  final String playOrder;
  final List<EpubNavigationLabel> navigationLabels;
  final EpubNavigationContent content;
  final List<EpubNavigationPoint> childNavigationPoints;

  @override
  List<Object?> get props => <Object?>[
        id,
        className,
        playOrder,
        navigationLabels,
        content,
        childNavigationPoints
      ];

  @override
  String toString() {
    return 'Id: $id, Content.Source: ${content.source}';
  }
}
