import 'package:equatable/equatable.dart';

class EpubNavigationLabel extends Equatable {
  const EpubNavigationLabel({required this.text});

  final String text;

  @override
  List<Object?> get props => <Object?>[text];

  @override
  String toString() => text;
}
