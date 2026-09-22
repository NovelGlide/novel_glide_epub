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
    final EpubGuide result = EpubGuide();
    result.items = _childrenNamed(guideNode, 'reference')
        .map(_readGuideReference)
        .toList();
    return result;
  }

  EpubGuideReference _readGuideReference(XmlElement guideReferenceNode) {
    final EpubGuideReference result = EpubGuideReference();
    for (XmlAttribute guideReferenceNodeAttribute
        in guideReferenceNode.attributes) {
      _applyGuideReferenceAttribute(result, guideReferenceNodeAttribute);
    }
    if (result.type == null || result.type!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB guide: item type is missing');
    }
    if (result.href == null || result.href!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB guide: item href is missing');
    }
    return result;
  }

  void _applyGuideReferenceAttribute(
      EpubGuideReference result, XmlAttribute attribute) {
    final String attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'type':
        result.type = attributeValue;
        break;
      case 'title':
        result.title = attributeValue;
        break;
      case 'href':
        result.href = attributeValue;
        break;
    }
  }

  EpubManifest readManifest(XmlElement manifestNode) {
    final EpubManifest result = EpubManifest();
    result.items =
        _childrenNamed(manifestNode, 'item').map(_readManifestItem).toList();
    return result;
  }

  EpubManifestItem _readManifestItem(XmlElement manifestItemNode) {
    final EpubManifestItem result = EpubManifestItem();
    for (XmlAttribute manifestItemNodeAttribute
        in manifestItemNode.attributes) {
      _applyManifestItemAttribute(result, manifestItemNodeAttribute);
    }
    _requireManifestItemFields(result);
    return result;
  }

  /// Id, href and media type are what every later lookup goes through, so an
  /// item missing any of them is refused where it is read rather than where it
  /// is used.
  void _requireManifestItemFields(EpubManifestItem result) {
    if (result.id == null || result.id!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB manifest: item ID is missing');
    }
    if (result.href == null || result.href!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB manifest: item href is missing');
    }
    if (result.mediaType == null || result.mediaType!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB manifest: item media type is missing');
    }
  }

  void _applyManifestItemAttribute(
      EpubManifestItem result, XmlAttribute attribute) {
    final String attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.id = attributeValue;
        break;
      case 'href':
        result.href = attributeValue;
        break;
      case 'media-type':
        result.mediaType = attributeValue;
        break;
      case 'media-overlay':
        result.mediaOverlay = attributeValue;
        break;
      case 'required-namespace':
        result.requiredNamespace = attributeValue;
        break;
      case 'required-modules':
        result.requiredModules = attributeValue;
        break;
      case 'fallback':
        result.fallback = attributeValue;
        break;
      case 'fallback-style':
        result.fallbackStyle = attributeValue;
        break;
      case 'properties':
        result.properties = attributeValue;
        break;
    }
  }

  EpubMetadata readMetadata(XmlElement metadataNode, EpubVersion? epubVersion) {
    final EpubMetadata result = EpubMetadata();
    result.titles = <String>[];
    result.creators = <EpubMetadataCreator>[];
    result.subjects = <String>[];
    result.publishers = <String>[];
    result.contributors = <EpubMetadataContributor>[];
    result.dates = <EpubMetadataDate>[];
    result.types = <String>[];
    result.formats = <String>[];
    result.identifiers = <EpubMetadataIdentifier>[];
    result.sources = <String>[];
    result.languages = <String>[];
    result.relations = <String>[];
    result.coverages = <String>[];
    result.rights = <String>[];
    result.metaItems = <EpubMetadataMeta>[];
    for (XmlElement metadataItemNode
        in metadataNode.children.whereType<XmlElement>()) {
      _addMetadataItem(result, metadataItemNode, epubVersion);
    }
    return result;
  }

  void _addMetadataItem(EpubMetadata result, XmlElement metadataItemNode,
      EpubVersion? epubVersion) {
    final String innerText = metadataItemNode.innerText;
    switch (metadataItemNode.name.local.toLowerCase()) {
      case 'title':
        result.titles!.add(innerText);
        break;
      case 'creator':
        result.creators!.add(readMetadataCreator(metadataItemNode));
        break;
      case 'subject':
        result.subjects!.add(innerText);
        break;
      case 'description':
        result.description = innerText;
        break;
      case 'publisher':
        result.publishers!.add(innerText);
        break;
      case 'contributor':
        result.contributors!.add(readMetadataContributor(metadataItemNode));
        break;
      case 'date':
        result.dates!.add(readMetadataDate(metadataItemNode));
        break;
      case 'type':
        result.types!.add(innerText);
        break;
      case 'format':
        result.formats!.add(innerText);
        break;
      case 'identifier':
        result.identifiers!.add(readMetadataIdentifier(metadataItemNode));
        break;
      case 'source':
        result.sources!.add(innerText);
        break;
      case 'language':
        result.languages!.add(innerText);
        break;
      case 'relation':
        result.relations!.add(innerText);
        break;
      case 'coverage':
        result.coverages!.add(innerText);
        break;
      case 'rights':
        result.rights!.add(innerText);
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
    if (epubVersion == EpubVersion.epub2) {
      result.metaItems!.add(readMetadataMetaVersion2(metadataItemNode));
    } else if (epubVersion == EpubVersion.epub3) {
      result.metaItems!.add(readMetadataMetaVersion3(metadataItemNode));
    }
  }

  Iterable<XmlElement> _childrenNamed(XmlElement parent, String localName) =>
      parent.children.whereType<XmlElement>().where(
          (XmlElement child) => child.name.local.toLowerCase() == localName);

  EpubMetadataContributor readMetadataContributor(
      XmlElement metadataContributorNode) {
    final EpubMetadataContributor result = EpubMetadataContributor();
    for (XmlAttribute metadataContributorNodeAttribute
        in metadataContributorNode.attributes) {
      final String attributeValue = metadataContributorNodeAttribute.value;
      switch (metadataContributorNodeAttribute.name.local.toLowerCase()) {
        case 'role':
          result.role = attributeValue;
          break;
        case 'file-as':
          result.fileAs = attributeValue;
          break;
      }
    }
    result.contributor = metadataContributorNode.innerText;
    return result;
  }

  EpubMetadataCreator readMetadataCreator(XmlElement metadataCreatorNode) {
    final EpubMetadataCreator result = EpubMetadataCreator();
    for (XmlAttribute metadataCreatorNodeAttribute
        in metadataCreatorNode.attributes) {
      final String attributeValue = metadataCreatorNodeAttribute.value;
      switch (metadataCreatorNodeAttribute.name.local.toLowerCase()) {
        case 'role':
          result.role = attributeValue;
          break;
        case 'file-as':
          result.fileAs = attributeValue;
          break;
      }
    }
    result.creator = metadataCreatorNode.innerText;
    return result;
  }

  EpubMetadataDate readMetadataDate(XmlElement metadataDateNode) {
    final EpubMetadataDate result = EpubMetadataDate();
    final String? eventAttribute = metadataDateNode.getAttribute('event',
        namespace: metadataDateNode.name.namespaceUri);
    if (eventAttribute != null && eventAttribute.isNotEmpty) {
      result.event = eventAttribute;
    }
    result.date = metadataDateNode.innerText;
    return result;
  }

  EpubMetadataIdentifier readMetadataIdentifier(
      XmlElement metadataIdentifierNode) {
    final EpubMetadataIdentifier result = EpubMetadataIdentifier();
    for (XmlAttribute metadataIdentifierNodeAttribute
        in metadataIdentifierNode.attributes) {
      final String attributeValue = metadataIdentifierNodeAttribute.value;
      switch (metadataIdentifierNodeAttribute.name.local.toLowerCase()) {
        case 'id':
          result.id = attributeValue;
          break;
        case 'scheme':
          result.scheme = attributeValue;
          break;
      }
    }
    result.identifier = metadataIdentifierNode.innerText;
    return result;
  }

  EpubMetadataMeta readMetadataMetaVersion2(XmlElement metadataMetaNode) {
    final EpubMetadataMeta result = EpubMetadataMeta();
    for (XmlAttribute metadataMetaNodeAttribute
        in metadataMetaNode.attributes) {
      final String attributeValue = metadataMetaNodeAttribute.value;
      switch (metadataMetaNodeAttribute.name.local.toLowerCase()) {
        case 'name':
          result.name = attributeValue;
          break;
        case 'content':
          result.content = attributeValue;
          break;
      }
    }
    return result;
  }

  EpubMetadataMeta readMetadataMetaVersion3(XmlElement metadataMetaNode) {
    final EpubMetadataMeta result = EpubMetadataMeta();
    result.attributes = <String, String>{};
    for (XmlAttribute metadataMetaNodeAttribute
        in metadataMetaNode.attributes) {
      final String attributeValue = metadataMetaNodeAttribute.value;
      result.attributes![metadataMetaNodeAttribute.name.local.toLowerCase()] =
          attributeValue;
      switch (metadataMetaNodeAttribute.name.local.toLowerCase()) {
        case 'id':
          result.id = attributeValue;
          break;
        case 'refines':
          result.refines = attributeValue;
          break;
        case 'property':
          result.property = attributeValue;
          break;
        case 'scheme':
          result.scheme = attributeValue;
          break;
      }
    }
    result.content = metadataMetaNode.innerText;
    return result;
  }

  Future<EpubPackage> readPackage(
      Archive epubArchive, String rootFilePath) async {
    final ArchiveFile? rootFileEntry = epubArchive.files.firstWhereOrNull(
        (ArchiveFile testFile) => testFile.name == rootFilePath);
    if (rootFileEntry == null) {
      throw const EpubMissingArchiveEntryException(
          'EPUB parsing error: root file not found in archive.');
    }
    final XmlDocument containerDocument =
        XmlDocument.parse(convert.utf8.decode(rootFileEntry.content));
    const String opfNamespace = 'http://www.idpf.org/2007/opf';
    final XmlElement packageNode = containerDocument
        .findElements('package', namespace: opfNamespace)
        .firstWhere((XmlElement? elem) => elem != null);
    final EpubPackage result = EpubPackage();
    final String? epubVersionValue = packageNode.getAttribute('version');
    if (epubVersionValue == '2.0') {
      result.version = EpubVersion.epub2;
    } else if (epubVersionValue == '3.0') {
      result.version = EpubVersion.epub3;
    } else {
      throw EpubUnsupportedVersionException(
          'Unsupported EPUB version: $epubVersionValue.');
    }
    final XmlElement? metadataNode = packageNode
        .findElements('metadata', namespace: opfNamespace)
        .cast<XmlElement?>()
        .firstWhere((XmlElement? elem) => elem != null);
    if (metadataNode == null) {
      throw const EpubMissingElementException(
          'EPUB parsing error: metadata not found in the package.');
    }
    final EpubMetadata metadata = readMetadata(metadataNode, result.version);
    result.metadata = metadata;
    final XmlElement? manifestNode = packageNode
        .findElements('manifest', namespace: opfNamespace)
        .cast<XmlElement?>()
        .firstWhere((XmlElement? elem) => elem != null);
    if (manifestNode == null) {
      throw const EpubMissingElementException(
          'EPUB parsing error: manifest not found in the package.');
    }
    final EpubManifest manifest = readManifest(manifestNode);
    result.manifest = manifest;

    final XmlElement? spineNode = packageNode
        .findElements('spine', namespace: opfNamespace)
        .cast<XmlElement?>()
        .firstWhere((XmlElement? elem) => elem != null);
    if (spineNode == null) {
      throw const EpubMissingElementException(
          'EPUB parsing error: spine not found in the package.');
    }
    final EpubSpine spine = readSpine(spineNode);
    result.spine = spine;
    final XmlElement? guideNode = packageNode
        .findElements('guide', namespace: opfNamespace)
        .firstWhereOrNull((XmlElement? elem) => elem != null);
    if (guideNode != null) {
      final EpubGuide guide = readGuide(guideNode);
      result.guide = guide;
    }
    return result;
  }

  EpubSpine readSpine(XmlElement spineNode) {
    final EpubSpine result = EpubSpine();
    result.items = <EpubSpineItemRef>[];
    final String? tocAttribute = spineNode.getAttribute('toc');
    result.tableOfContents = tocAttribute;
    final String? pageProgression =
        spineNode.getAttribute('page-progression-direction');
    result.ltr =
        (pageProgression == null) || pageProgression.toLowerCase() == 'ltr';
    spineNode.children
        .whereType<XmlElement>()
        .forEach((XmlElement spineItemNode) {
      if (spineItemNode.name.local.toLowerCase() == 'itemref') {
        final EpubSpineItemRef spineItemRef = EpubSpineItemRef();
        final String? idRefAttribute = spineItemNode.getAttribute('idref');
        if (idRefAttribute == null || idRefAttribute.isEmpty) {
          throw const EpubMissingValueException(
              'Incorrect EPUB spine: item ID ref is missing');
        }
        spineItemRef.idRef = idRefAttribute;
        final String? linearAttribute = spineItemNode.getAttribute('linear');
        spineItemRef.isLinear =
            linearAttribute == null || (linearAttribute.toLowerCase() == 'no');
        result.items!.add(spineItemRef);
      }
    });
    return result;
  }
}
