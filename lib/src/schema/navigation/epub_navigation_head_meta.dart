import 'package:equatable/equatable.dart';

class EpubNavigationHeadMeta extends Equatable {
  const EpubNavigationHeadMeta(
      {required this.name, required this.content, this.scheme});

  final String name;
  final String content;
  final String? scheme;

  @override
  List<Object?> get props => <Object?>[name, content, scheme];
}
