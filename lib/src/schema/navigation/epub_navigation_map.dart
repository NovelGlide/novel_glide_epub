import 'package:equatable/equatable.dart';

import 'epub_navigation_point.dart';

class EpubNavigationMap extends Equatable {
  const EpubNavigationMap({required this.points});

  /// Empty when the `<navMap>` (or the nav document's `<ol>`) has no entry,
  /// although both formats require one.
  final List<EpubNavigationPoint> points;

  @override
  List<Object?> get props => <Object?>[points];
}
