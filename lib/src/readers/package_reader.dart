import 'dart:async';
import 'dart:convert' as convert;

import 'package:archive/archive.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:xml/xml.dart';

import '../epub_exception.dart';
import '../schema/opf/epub_guide.dart';
import '../schema/opf/epub_guide_reference.dart';
import '../schema/opf/epub_manifest.dart';
import '../schema/opf/epub_manifest_item.dart';
import '../schema/opf/epub_metadata.dart';
import '../schema/opf/epub_metadata_contributor.dart';
import '../schema/opf/epub_metadata_creator.dart';
import '../schema/opf/epub_metadata_date.dart';
import '../schema/opf/epub_metadata_identifier.dart';
import '../schema/opf/epub_metadata_meta.dart';
import '../schema/opf/epub_package.dart';
import '../schema/opf/epub_spine.dart';
import '../schema/opf/epub_spine_item_ref.dart';
import '../schema/opf/epub_version.dart';

class PackageReader {
  const PackageReader();

  EpubGuide readGuide(XmlElement guideNode) {
    var result = EpubGuide();
    result.Items = _childrenNamed(guideNode, 'reference')
        .map(_readGuideReference)
        .toList();
    return result;
  }

  EpubGuideReference _readGuideReference(XmlElement guideReferenceNode) {
    var result = EpubGuideReference();
    for (var guideReferenceNodeAttribute in guideReferenceNode.attributes) {
      _applyGuideReferenceAttribute(result, guideReferenceNodeAttribute);
    }
    if (result.Type == null || result.Type!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB guide: item type is missing');
    }
    if (result.Href == null || result.Href!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB guide: item href is missing');
    }
    return result;
  }

  void _applyGuideReferenceAttribute(
      EpubGuideReference result, XmlAttribute attribute) {
    var attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'type':
        result.Type = attributeValue;
        break;
      case 'title':
        result.Title = attributeValue;
        break;
      case 'href':
        result.Href = attributeValue;
        break;
    }
  }

  EpubManifest readManifest(XmlElement manifestNode) {
    var result = EpubManifest();
    result.Items =
        _childrenNamed(manifestNode, 'item').map(_readManifestItem).toList();
    return result;
  }

  EpubManifestItem _readManifestItem(XmlElement manifestItemNode) {
    var result = EpubManifestItem();
    for (var manifestItemNodeAttribute in manifestItemNode.attributes) {
      _applyManifestItemAttribute(result, manifestItemNodeAttribute);
    }
    _requireManifestItemFields(result);
    return result;
  }

  /// Id, href and media type are what every later lookup goes through, so an
  /// item missing any of them is refused where it is read rather than where it
  /// is used.
  void _requireManifestItemFields(EpubManifestItem result) {
    if (result.Id == null || result.Id!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB manifest: item ID is missing');
    }
    if (result.Href == null || result.Href!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB manifest: item href is missing');
    }
    if (result.MediaType == null || result.MediaType!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB manifest: item media type is missing');
    }
  }

  void _applyManifestItemAttribute(
      EpubManifestItem result, XmlAttribute attribute) {
    var attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.Id = attributeValue;
        break;
      case 'href':
        result.Href = attributeValue;
        break;
      case 'media-type':
        result.MediaType = attributeValue;
        break;
      case 'media-overlay':
        result.MediaOverlay = attributeValue;
        break;
      case 'required-namespace':
        result.RequiredNamespace = attributeValue;
        break;
      case 'required-modules':
        result.RequiredModules = attributeValue;
        break;
      case 'fallback':
        result.Fallback = attributeValue;
        break;
      case 'fallback-style':
        result.FallbackStyle = attributeValue;
        break;
      case 'properties':
        result.Properties = attributeValue;
        break;
    }
  }

  EpubMetadata readMetadata(XmlElement metadataNode, EpubVersion? epubVersion) {
    var result = EpubMetadata();
    result.Titles = <String>[];
    result.Creators = <EpubMetadataCreator>[];
    result.Subjects = <String>[];
    result.Publishers = <String>[];
    result.Contributors = <EpubMetadataContributor>[];
    result.Dates = <EpubMetadataDate>[];
    result.Types = <String>[];
    result.Formats = <String>[];
    result.Identifiers = <EpubMetadataIdentifier>[];
    result.Sources = <String>[];
    result.Languages = <String>[];
    result.Relations = <String>[];
    result.Coverages = <String>[];
    result.Rights = <String>[];
    result.MetaItems = <EpubMetadataMeta>[];
    for (var metadataItemNode
        in metadataNode.children.whereType<XmlElement>()) {
      _addMetadataItem(result, metadataItemNode, epubVersion);
    }
    return result;
  }

  void _addMetadataItem(EpubMetadata result, XmlElement metadataItemNode,
      EpubVersion? epubVersion) {
    var innerText = metadataItemNode.text;
    switch (metadataItemNode.name.local.toLowerCase()) {
      case 'title':
        result.Titles!.add(innerText);
        break;
      case 'creator':
        result.Creators!.add(readMetadataCreator(metadataItemNode));
        break;
      case 'subject':
        result.Subjects!.add(innerText);
        break;
      case 'description':
        result.Description = innerText;
        break;
      case 'publisher':
        result.Publishers!.add(innerText);
        break;
      case 'contributor':
        result.Contributors!.add(readMetadataContributor(metadataItemNode));
        break;
      case 'date':
        result.Dates!.add(readMetadataDate(metadataItemNode));
        break;
      case 'type':
        result.Types!.add(innerText);
        break;
      case 'format':
        result.Formats!.add(innerText);
        break;
      case 'identifier':
        result.Identifiers!.add(readMetadataIdentifier(metadataItemNode));
        break;
      case 'source':
        result.Sources!.add(innerText);
        break;
      case 'language':
        result.Languages!.add(innerText);
        break;
      case 'relation':
        result.Relations!.add(innerText);
        break;
      case 'coverage':
        result.Coverages!.add(innerText);
        break;
      case 'rights':
        result.Rights!.add(innerText);
        break;
      case 'meta':
        _addMetadataMeta(result, metadataItemNode, epubVersion);
        break;
    }
  }

  /// `<meta>` is the one metadata element whose shape changed between EPUB2
  /// and EPUB3, so the version decides which reader runs; a version this
  /// parser does not know contributes no meta items at all.
  void _addMetadataMeta(EpubMetadata result, XmlElement metadataItemNode,
      EpubVersion? epubVersion) {
    if (epubVersion == EpubVersion.Epub2) {
      result.MetaItems!.add(readMetadataMetaVersion2(metadataItemNode));
    } else if (epubVersion == EpubVersion.Epub3) {
      result.MetaItems!.add(readMetadataMetaVersion3(metadataItemNode));
    }
  }

  Iterable<XmlElement> _childrenNamed(XmlElement parent, String localName) =>
      parent.children.whereType<XmlElement>().where(
          (XmlElement child) => child.name.local.toLowerCase() == localName);

  EpubMetadataContributor readMetadataContributor(
      XmlElement metadataContributorNode) {
    var result = EpubMetadataContributor();
    for (var metadataContributorNodeAttribute
        in metadataContributorNode.attributes) {
      var attributeValue = metadataContributorNodeAttribute.value;
      switch (metadataContributorNodeAttribute.name.local.toLowerCase()) {
        case 'role':
          result.Role = attributeValue;
          break;
        case 'file-as':
          result.FileAs = attributeValue;
          break;
      }
    }
    result.Contributor = metadataContributorNode.text;
    return result;
  }

  EpubMetadataCreator readMetadataCreator(XmlElement metadataCreatorNode) {
    var result = EpubMetadataCreator();
    for (var metadataCreatorNodeAttribute in metadataCreatorNode.attributes) {
      var attributeValue = metadataCreatorNodeAttribute.value;
      switch (metadataCreatorNodeAttribute.name.local.toLowerCase()) {
        case 'role':
          result.Role = attributeValue;
          break;
        case 'file-as':
          result.FileAs = attributeValue;
          break;
      }
    }
    result.Creator = metadataCreatorNode.text;
    return result;
  }

  EpubMetadataDate readMetadataDate(XmlElement metadataDateNode) {
    var result = EpubMetadataDate();
    var eventAttribute = metadataDateNode.getAttribute('event',
        namespace: metadataDateNode.name.namespaceUri);
    if (eventAttribute != null && eventAttribute.isNotEmpty) {
      result.Event = eventAttribute;
    }
    result.Date = metadataDateNode.text;
    return result;
  }

  EpubMetadataIdentifier readMetadataIdentifier(
      XmlElement metadataIdentifierNode) {
    var result = EpubMetadataIdentifier();
    for (var metadataIdentifierNodeAttribute
        in metadataIdentifierNode.attributes) {
      var attributeValue = metadataIdentifierNodeAttribute.value;
      switch (metadataIdentifierNodeAttribute.name.local.toLowerCase()) {
        case 'id':
          result.Id = attributeValue;
          break;
        case 'scheme':
          result.Scheme = attributeValue;
          break;
      }
    }
    result.Identifier = metadataIdentifierNode.text;
    return result;
  }

  EpubMetadataMeta readMetadataMetaVersion2(XmlElement metadataMetaNode) {
    var result = EpubMetadataMeta();
    for (var metadataMetaNodeAttribute in metadataMetaNode.attributes) {
      var attributeValue = metadataMetaNodeAttribute.value;
      switch (metadataMetaNodeAttribute.name.local.toLowerCase()) {
        case 'name':
          result.Name = attributeValue;
          break;
        case 'content':
          result.Content = attributeValue;
          break;
      }
    }
    return result;
  }

  EpubMetadataMeta readMetadataMetaVersion3(XmlElement metadataMetaNode) {
    var result = EpubMetadataMeta();
    result.Attributes = {};
    for (var metadataMetaNodeAttribute in metadataMetaNode.attributes) {
      var attributeValue = metadataMetaNodeAttribute.value;
      result.Attributes![metadataMetaNodeAttribute.name.local.toLowerCase()] =
          attributeValue;
      switch (metadataMetaNodeAttribute.name.local.toLowerCase()) {
        case 'id':
          result.Id = attributeValue;
          break;
        case 'refines':
          result.Refines = attributeValue;
          break;
        case 'property':
          result.Property = attributeValue;
          break;
        case 'scheme':
          result.Scheme = attributeValue;
          break;
      }
    }
    result.Content = metadataMetaNode.text;
    return result;
  }

  Future<EpubPackage> readPackage(
      Archive epubArchive, String rootFilePath) async {
    var rootFileEntry = epubArchive.files.firstWhereOrNull(
        (ArchiveFile testFile) => testFile.name == rootFilePath);
    if (rootFileEntry == null) {
      throw EpubMissingArchiveEntryException(
          'EPUB parsing error: root file not found in archive.');
    }
    var containerDocument =
        XmlDocument.parse(convert.utf8.decode(rootFileEntry.content));
    var opfNamespace = 'http://www.idpf.org/2007/opf';
    var packageNode = containerDocument
        .findElements('package', namespace: opfNamespace)
        .firstWhere((XmlElement? elem) => elem != null);
    var result = EpubPackage();
    var epubVersionValue = packageNode.getAttribute('version');
    if (epubVersionValue == '2.0') {
      result.Version = EpubVersion.Epub2;
    } else if (epubVersionValue == '3.0') {
      result.Version = EpubVersion.Epub3;
    } else {
      throw EpubUnsupportedVersionException(
          'Unsupported EPUB version: $epubVersionValue.');
    }
    var metadataNode = packageNode
        .findElements('metadata', namespace: opfNamespace)
        .cast<XmlElement?>()
        .firstWhere((XmlElement? elem) => elem != null);
    if (metadataNode == null) {
      throw EpubMissingElementException(
          'EPUB parsing error: metadata not found in the package.');
    }
    var metadata = readMetadata(metadataNode, result.Version);
    result.Metadata = metadata;
    var manifestNode = packageNode
        .findElements('manifest', namespace: opfNamespace)
        .cast<XmlElement?>()
        .firstWhere((XmlElement? elem) => elem != null);
    if (manifestNode == null) {
      throw EpubMissingElementException(
          'EPUB parsing error: manifest not found in the package.');
    }
    var manifest = readManifest(manifestNode);
    result.Manifest = manifest;

    var spineNode = packageNode
        .findElements('spine', namespace: opfNamespace)
        .cast<XmlElement?>()
        .firstWhere((XmlElement? elem) => elem != null);
    if (spineNode == null) {
      throw EpubMissingElementException(
          'EPUB parsing error: spine not found in the package.');
    }
    var spine = readSpine(spineNode);
    result.Spine = spine;
    var guideNode = packageNode
        .findElements('guide', namespace: opfNamespace)
        .firstWhereOrNull((XmlElement? elem) => elem != null);
    if (guideNode != null) {
      var guide = readGuide(guideNode);
      result.Guide = guide;
    }
    return result;
  }

  EpubSpine readSpine(XmlElement spineNode) {
    var result = EpubSpine();
    result.Items = <EpubSpineItemRef>[];
    var tocAttribute = spineNode.getAttribute('toc');
    result.TableOfContents = tocAttribute;
    var pageProgression = spineNode.getAttribute('page-progression-direction');
    result.ltr =
        ((pageProgression == null) || pageProgression.toLowerCase() == 'ltr');
    spineNode.children
        .whereType<XmlElement>()
        .forEach((XmlElement spineItemNode) {
      if (spineItemNode.name.local.toLowerCase() == 'itemref') {
        var spineItemRef = EpubSpineItemRef();
        var idRefAttribute = spineItemNode.getAttribute('idref');
        if (idRefAttribute == null || idRefAttribute.isEmpty) {
          throw EpubMissingValueException(
              'Incorrect EPUB spine: item ID ref is missing');
        }
        spineItemRef.IdRef = idRefAttribute;
        var linearAttribute = spineItemNode.getAttribute('linear');
        spineItemRef.IsLinear =
            linearAttribute == null || (linearAttribute.toLowerCase() == 'no');
        result.Items!.add(spineItemRef);
      }
    });
    return result;
  }
}
