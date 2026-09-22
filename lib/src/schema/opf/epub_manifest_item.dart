import 'package:quiver/core.dart';

class EpubManifestItem {
  String? id;
  String? href;
  String? mediaType;
  String? mediaOverlay;
  String? requiredNamespace;
  String? requiredModules;
  String? fallback;
  String? fallbackStyle;
  String? properties;

  @override
  int get hashCode => hashObjects(<Object?>[
        id.hashCode,
        href.hashCode,
        mediaType.hashCode,
        mediaOverlay.hashCode,
        requiredNamespace.hashCode,
        requiredModules.hashCode,
        fallback.hashCode,
        fallbackStyle.hashCode,
        properties.hashCode
      ]);

  @override
  bool operator ==(Object other) =>
      other is EpubManifestItem &&
      _describesSameResource(other) &&
      _hasSameFallbackChain(other);

  /// The half of the item that says WHAT it is: the resource it points at and
  /// how a reading system is meant to treat it.
  bool _describesSameResource(EpubManifestItem other) =>
      id == other.id &&
      href == other.href &&
      mediaType == other.mediaType &&
      mediaOverlay == other.mediaOverlay &&
      properties == other.properties;

  /// The half that says what to do when the resource CANNOT be used: the
  /// EPUB2 fallback and required-module attributes.
  bool _hasSameFallbackChain(EpubManifestItem other) =>
      fallback == other.fallback &&
      fallbackStyle == other.fallbackStyle &&
      requiredNamespace == other.requiredNamespace &&
      requiredModules == other.requiredModules;

  @override
  String toString() {
    return 'Id: $id, Href = $href, MediaType = $mediaType, Properties = $properties, MediaOverlay = $mediaOverlay';
  }
}
