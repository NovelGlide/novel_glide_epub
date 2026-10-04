import 'package:equatable/equatable.dart';

class EpubManifestItem extends Equatable {
  const EpubManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    this.mediaOverlay,
    this.requiredNamespace,
    this.requiredModules,
    this.fallback,
    this.fallbackStyle,
    this.properties,
  });

  final String id;

  /// As the manifest wrote it, percent-escapes included.
  final String href;
  final String mediaType;
  final String? mediaOverlay;
  final String? requiredNamespace;
  final String? requiredModules;
  final String? fallback;
  final String? fallbackStyle;
  final String? properties;

  @override
  List<Object?> get props => <Object?>[
        id,
        href,
        mediaType,
        mediaOverlay,
        requiredNamespace,
        requiredModules,
        fallback,
        fallbackStyle,
        properties
      ];

  @override
  String toString() {
    return 'Id: $id, Href = $href, MediaType = $mediaType, Properties = $properties, MediaOverlay = $mediaOverlay';
  }
}
