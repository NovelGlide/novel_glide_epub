import 'package:equatable/equatable.dart';

class EpubMetadataDate extends Equatable {
  const EpubMetadataDate({required this.date, this.event});

  /// The element's text; empty when the element is.
  final String date;

  /// Null when the date carries no `opf:event`, or an empty one.
  final String? event;

  @override
  List<Object?> get props => <Object?>[date, event];
}
