import 'package:quiver/core.dart';

class EpubSpineItemRef {
  const EpubSpineItemRef({required this.idRef, required this.isLinear});

  final String idRef;
  final bool isLinear;

  @override
  int get hashCode => hash2(idRef.hashCode, isLinear.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubSpineItemRef) {
      return false;
    }

    return idRef == other.idRef && isLinear == other.isLinear;
  }

  @override
  String toString() {
    return 'IdRef: $idRef';
  }
}
