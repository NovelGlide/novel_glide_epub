import 'package:quiver/core.dart';

class EpubManifestItem {
  String? Id;
  String? Href;
  String? MediaType;
  String? MediaOverlay;
  String? RequiredNamespace;
  String? RequiredModules;
  String? Fallback;
  String? FallbackStyle;
  String? Properties;

  @override
  int get hashCode => hashObjects([
        Id.hashCode,
        Href.hashCode,
        MediaType.hashCode,
        MediaOverlay.hashCode,
        RequiredNamespace.hashCode,
        RequiredModules.hashCode,
        Fallback.hashCode,
        FallbackStyle.hashCode,
        Properties.hashCode
      ]);

  @override
  bool operator ==(Object other) =>
      other is EpubManifestItem &&
      _describesSameResource(other) &&
      _hasSameFallbackChain(other);

  /// The half of the item that says WHAT it is: the resource it points at and
  /// how a reading system is meant to treat it.
  bool _describesSameResource(EpubManifestItem other) =>
      Id == other.Id &&
      Href == other.Href &&
      MediaType == other.MediaType &&
      MediaOverlay == other.MediaOverlay &&
      Properties == other.Properties;

  /// The half that says what to do when the resource CANNOT be used: the
  /// EPUB2 fallback and required-module attributes.
  bool _hasSameFallbackChain(EpubManifestItem other) =>
      Fallback == other.Fallback &&
      FallbackStyle == other.FallbackStyle &&
      RequiredNamespace == other.RequiredNamespace &&
      RequiredModules == other.RequiredModules;

  @override
  String toString() {
    return 'Id: $Id, Href = $Href, MediaType = $MediaType, Properties = $Properties, MediaOverlay = $MediaOverlay';
  }
}
