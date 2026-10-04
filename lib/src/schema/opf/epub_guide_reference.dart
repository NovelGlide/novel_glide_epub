import 'package:equatable/equatable.dart';

class EpubGuideReference extends Equatable {
  const EpubGuideReference({
    required this.type,
    required this.href,
    this.title,
  });

  final String type;
  final String href;

  /// Null when the reference has no `title`, which OPF 2 makes optional.
  final String? title;

  @override
  List<Object?> get props => <Object?>[type, href, title];

  @override
  String toString() {
    return 'Type: $type, Href: $href';
  }
}
