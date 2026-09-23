import 'package:quiver/core.dart';

class EpubMetadataDate {
  const EpubMetadataDate({required this.date, this.event});

  /// The element's text; empty when the element is.
  final String date;

  /// Null when the date carries no `opf:event`, or an empty one.
  final String? event;

  @override
  int get hashCode => hash2(date.hashCode, event.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataDate) {
      return false;
    }
    return date == other.date && event == other.event;
  }
}
