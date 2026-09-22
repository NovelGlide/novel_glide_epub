import 'package:quiver/core.dart';

class EpubMetadataDate {
  String? date;
  String? event;

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
