import 'package:quiver/core.dart';

class EpubMetadataDate {
  String? Date;
  String? Event;

  @override
  int get hashCode => hash2(Date.hashCode, Event.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubMetadataDate) {
      return false;
    }
    return Date == other.Date && Event == other.Event;
  }
}
