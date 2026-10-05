import 'package:equatable/equatable.dart';

import 'epub_manifest_item.dart';

class EpubManifest extends Equatable {
  const EpubManifest({required this.items});

  /// Empty when the `<manifest>` has no `<item>`, although OPF requires at
  /// least one.
  final List<EpubManifestItem> items;

  @override
  List<Object?> get props => <Object?>[items];
}
