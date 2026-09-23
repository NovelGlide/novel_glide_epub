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
import '../utils/unmodifiable_iterable.dart';
import '../utils/xml_attribute_reader.dart';

class PackageReader {
  const PackageReader();

  XmlAttributeReader get _attributes => const XmlAttributeReader();

  EpubGuide readGuide(XmlElement guideNode) {
    return EpubGuide(
        items: _childrenNamed(guideNode, 'reference')
            .map(_readGuideReference)
            .toUnmodifiableList());
  }

  EpubGuideReference _readGuideReference(XmlElement guideReferenceNode) {
    final String? type = _attributes.read(guideReferenceNode, 'type');
    if (type == null || type.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB guide: item type is missing');
    }
    final String? href = _attributes.read(guideReferenceNode, 'href');
    if (href == null || href.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB guide: item href is missing');
    }
    return EpubGuideReference(
      type: type,
      href: href,
      title: _attributes.read(guideReferenceNode, 'title'),
    );
  }

  EpubManifest readManifest(XmlElement manifestNode) {
    return EpubManifest(
        items: _childrenNamed(manifestNode, 'item')
            .map(_readManifestItem)
            .toUnmodifiableList());
  }

  /// Id, href and media type are what every later lookup goes through, so an
  /// item missing any of them is refused where it is read rather than where it
  /// is used.
  EpubManifestItem _readManifestItem(XmlElement manifestItemNode) {
    final Map<String, String> attributes =
        _attributes.readAll(manifestItemNode);
    return EpubManifestItem(
      id: _requireManifestItemValue(attributes, 'id', 'item ID'),
      href: _requireManifestItemValue(attributes, 'href', 'item href'),
      mediaType: _requireManifestItemValue(
          attributes, 'media-type', 'item media type'),
      mediaOverlay: attributes['media-overlay'],
      requiredNamespace: attributes['required-namespace'],
      requiredModules: attributes['required-modules'],
      fallback: attributes['fallback'],
      fallbackStyle: attributes['fallback-style'],
      properties: attributes['properties'],
    );
  }

  String _requireManifestItemValue(
      Map<String, String> attributes, String name, String description) {
    final String? value = attributes[name];
    if (value == null || value.isEmpty) {
      throw EpubMissingValueException(
          'Incorrect EPUB manifest: $description is missing');
    }
    return value;
  }

  EpubMetadata readMetadata(XmlElement metadataNode, EpubVersion epubVersion) {
    List<String> textsOf(String localName) =>
        _childrenNamed(metadataNode, localName)
            .map((XmlElement element) => element.innerText)
            .toUnmodifiableList();

    return EpubMetadata(
      titles: textsOf('title'),
      creators: _childrenNamed(metadataNode, 'creator')
          .map(readMetadataCreator)
          .toUnmodifiableList(),
      subjects: textsOf('subject'),
      descriptions: textsOf('description'),
      publishers: textsOf('publisher'),
      contributors: _childrenNamed(metadataNode, 'contributor')
          .map(readMetadataContributor)
          .toUnmodifiableList(),
      dates: _childrenNamed(metadataNode, 'date')
          .map(readMetadataDate)
          .toUnmodifiableList(),
      types: textsOf('type'),
      formats: textsOf('format'),
      identifiers: _childrenNamed(metadataNode, 'identifier')
          .map(readMetadataIdentifier)
          .toUnmodifiableList(),
      sources: textsOf('source'),
      languages: textsOf('language'),
      relations: textsOf('relation'),
      coverages: textsOf('coverage'),
      rights: textsOf('rights'),
      metaItems: _childrenNamed(metadataNode, 'meta')
          .map(
              (XmlElement metaNode) => _readMetadataMeta(metaNode, epubVersion))
          .toUnmodifiableList(),
    );
  }

  /// `<meta>` is the one metadata element whose shape changed between EPUB2
  /// and EPUB3, so the version decides which reader runs.
  EpubMetadataMeta _readMetadataMeta(
          XmlElement metadataMetaNode, EpubVersion epubVersion) =>
      switch (epubVersion) {
        EpubVersion.epub2 => readMetadataMetaVersion2(metadataMetaNode),
        EpubVersion.epub3 => readMetadataMetaVersion3(metadataMetaNode),
      };

  Iterable<XmlElement> _childrenNamed(XmlElement parent, String localName) =>
      parent.children.whereType<XmlElement>().where(
          (XmlElement child) => child.name.local.toLowerCase() == localName);

  EpubMetadataContributor readMetadataContributor(
      XmlElement metadataContributorNode) {
    return EpubMetadataContributor(
      contributor: metadataContributorNode.innerText,
      fileAs: _attributes.read(metadataContributorNode, 'file-as'),
      role: _attributes.read(metadataContributorNode, 'role'),
    );
  }

  EpubMetadataCreator readMetadataCreator(XmlElement metadataCreatorNode) {
    return EpubMetadataCreator(
      creator: metadataCreatorNode.innerText,
      fileAs: _attributes.read(metadataCreatorNode, 'file-as'),
      role: _attributes.read(metadataCreatorNode, 'role'),
    );
  }

  EpubMetadataDate readMetadataDate(XmlElement metadataDateNode) {
    final String? eventAttribute = metadataDateNode.getAttribute('event',
        namespace: metadataDateNode.name.namespaceUri);
    return EpubMetadataDate(
      date: metadataDateNode.innerText,
      event: eventAttribute == null || eventAttribute.isEmpty
          ? null
          : eventAttribute,
    );
  }

  EpubMetadataIdentifier readMetadataIdentifier(
      XmlElement metadataIdentifierNode) {
    return EpubMetadataIdentifier(
      identifier: metadataIdentifierNode.innerText,
      id: _attributes.read(metadataIdentifierNode, 'id'),
      scheme: _attributes.read(metadataIdentifierNode, 'scheme'),
    );
  }

  EpubMetadataMeta readMetadataMetaVersion2(XmlElement metadataMetaNode) {
    final Map<String, String> attributes =
        Map<String, String>.unmodifiable(_attributes.readAll(metadataMetaNode));
    return EpubMetadataMeta(
      name: attributes['name'],
      content: attributes['content'] ?? '',
      attributes: attributes,
    );
  }

  EpubMetadataMeta readMetadataMetaVersion3(XmlElement metadataMetaNode) {
    final Map<String, String> attributes =
        Map<String, String>.unmodifiable(_attributes.readAll(metadataMetaNode));
    return EpubMetadataMeta(
      content: metadataMetaNode.innerText,
      id: attributes['id'],
      refines: attributes['refines'],
      property: attributes['property'],
      scheme: attributes['scheme'],
      attributes: attributes,
    );
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
    final EpubVersion version = _readVersion(packageNode);

    XmlElement requirePackageChild(String name) {
      final XmlElement? node =
          packageNode.findElements(name, namespace: opfNamespace).firstOrNull;
      if (node == null) {
        throw EpubMissingElementException(
            'EPUB parsing error: $name not found in the package.');
      }
      return node;
    }

    final XmlElement? guideNode =
        packageNode.findElements('guide', namespace: opfNamespace).firstOrNull;
    return EpubPackage(
      version: version,
      metadata: readMetadata(requirePackageChild('metadata'), version),
      manifest: readManifest(requirePackageChild('manifest')),
      spine: readSpine(requirePackageChild('spine')),
      guide: guideNode == null ? null : readGuide(guideNode),
    );
  }

  EpubVersion _readVersion(XmlElement packageNode) {
    final String? epubVersionValue = packageNode.getAttribute('version');
    switch (epubVersionValue) {
      case '2.0':
        return EpubVersion.epub2;
      case '3.0':
        return EpubVersion.epub3;
      default:
        throw EpubUnsupportedVersionException(
            'Unsupported EPUB version: $epubVersionValue.');
    }
  }

  EpubSpine readSpine(XmlElement spineNode) {
    final String? pageProgression =
        spineNode.getAttribute('page-progression-direction');
    return EpubSpine(
      tableOfContents: spineNode.getAttribute('toc'),
      ltr: (pageProgression == null) || pageProgression.toLowerCase() == 'ltr',
      items: _childrenNamed(spineNode, 'itemref')
          .map(_readSpineItemRef)
          .toUnmodifiableList(),
    );
  }

  EpubSpineItemRef _readSpineItemRef(XmlElement spineItemNode) {
    final String? idRefAttribute = spineItemNode.getAttribute('idref');
    if (idRefAttribute == null || idRefAttribute.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB spine: item ID ref is missing');
    }
    final String? linearAttribute = spineItemNode.getAttribute('linear');
    return EpubSpineItemRef(
      idRef: idRefAttribute,
      isLinear:
          linearAttribute == null || (linearAttribute.toLowerCase() == 'no'),
    );
  }
}
