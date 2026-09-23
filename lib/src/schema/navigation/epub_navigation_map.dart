import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_point.dart';

class EpubNavigationMap {
  const EpubNavigationMap({required this.points});

  /// Empty when the `<navMap>` (or the nav document's `<ol>`) has no entry,
  /// although both formats require one.
  final List<EpubNavigationPoint> points;

  @override
  int get hashCode =>
      hashObjects(points.map((EpubNavigationPoint point) => point.hashCode));

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationMap) {
      return false;
    }

    return collections.listsEqual(points, other.points);
  }
}
