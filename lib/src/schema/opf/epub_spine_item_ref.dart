import 'package:quiver/core.dart';

class EpubSpineItemRef {
  String? IdRef;
  bool? IsLinear;

  @override
  int get hashCode => hash2(IdRef.hashCode, IsLinear.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubSpineItemRef) {
      return false;
    }

    return IdRef == other.IdRef && IsLinear == other.IsLinear;
  }

  @override
  String toString() {
    return 'IdRef: $IdRef';
  }
}
