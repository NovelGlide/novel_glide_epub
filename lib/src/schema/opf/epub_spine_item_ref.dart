import 'package:equatable/equatable.dart';

class EpubSpineItemRef extends Equatable {
  const EpubSpineItemRef({required this.idRef, required this.isLinear});

  final String idRef;
  final bool isLinear;

  @override
  List<Object?> get props => <Object?>[idRef, isLinear];

  @override
  String toString() {
    return 'IdRef: $idRef';
  }
}
