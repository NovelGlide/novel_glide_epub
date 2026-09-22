import 'dart:async';
import 'dart:convert' as convert;

import 'package:archive/archive.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart' as xml;

import '../epub_exception.dart';
import '../schema/navigation/epub_navigation.dart';
import '../schema/navigation/epub_navigation_content.dart';
import '../schema/navigation/epub_navigation_doc_author.dart';
import '../schema/navigation/epub_navigation_doc_title.dart';
import '../schema/navigation/epub_navigation_head.dart';
import '../schema/navigation/epub_navigation_head_meta.dart';
import '../schema/navigation/epub_navigation_label.dart';
import '../schema/navigation/epub_navigation_list.dart';
import '../schema/navigation/epub_navigation_map.dart';
import '../schema/navigation/epub_navigation_page_list.dart';
import '../schema/navigation/epub_navigation_page_target.dart';
import '../schema/navigation/epub_navigation_page_target_type.dart';
import '../schema/navigation/epub_navigation_point.dart';
import '../schema/navigation/epub_navigation_target.dart';
import '../schema/opf/epub_manifest_item.dart';
import '../schema/opf/epub_package.dart';
import '../schema/opf/epub_version.dart';
import '../utils/enum_from_string.dart';
import '../utils/zip_path_resolver.dart';

class NavigationReader {
  const NavigationReader();

  static const String _ncxNamespace = 'http://www.daisy.org/z3986/2005/ncx/';

  ZipPathResolver get _pathResolver => const ZipPathResolver();

  Future<EpubNavigation> readNavigation(Archive epubArchive,
      String contentDirectoryPath, EpubPackage package) async {
    if (package.version == EpubVersion.epub2) {
      return _readEpub2Navigation(epubArchive, contentDirectoryPath, package);
    }
    return _readEpub3Navigation(epubArchive, contentDirectoryPath, package);
  }

  /// The EPUB2 table of contents: an NCX document named by the spine's `toc`
  /// attribute.
  EpubNavigation _readEpub2Navigation(
      Archive epubArchive, String contentDirectoryPath, EpubPackage package) {
    final xml.XmlElement ncxNode =
        _readNcxElement(epubArchive, contentDirectoryPath, package);
    final EpubNavigation result = EpubNavigation();

    result.head = readNavigationHead(_requireElement(
        ncxNode.findAllElements('head', namespace: _ncxNamespace),
        element: 'head',
        document: 'TOC file'));
    result.docTitle = readNavigationDocTitle(_requireElement(
        ncxNode.findElements('docTitle', namespace: _ncxNamespace),
        element: 'docTitle',
        document: 'TOC file'));
    result.docAuthors = ncxNode
        .findElements('docAuthor', namespace: _ncxNamespace)
        .map(readNavigationDocAuthor)
        .toList();
    result.navMap = readNavigationMap(_requireElement(
        ncxNode.findElements('navMap', namespace: _ncxNamespace),
        element: 'navMap',
        document: 'TOC file'));

    // A pageList is optional, so its absence is not a parsing error.
    final xml.XmlElement? pageListNode =
        ncxNode.findElements('pageList', namespace: _ncxNamespace).firstOrNull;
    if (pageListNode != null) {
      result.pageList = readNavigationPageList(pageListNode);
    }

    result.navLists = ncxNode
        .findElements('navList', namespace: _ncxNamespace)
        .map(readNavigationList)
        .toList();
    return result;
  }

  /// Walks spine `toc` attribute -> manifest item -> archive entry -> the
  /// `ncx` root element, refusing the book at whichever step first comes up
  /// empty.
  xml.XmlElement _readNcxElement(
      Archive epubArchive, String contentDirectoryPath, EpubPackage package) {
    final String? tocId = package.spine!.tableOfContents;
    if (tocId == null || tocId.isEmpty) {
      throw const EpubMissingValueException(
          'EPUB parsing error: TOC ID is empty.');
    }

    final EpubManifestItem? tocManifestItem = package.manifest!.items!
        .firstWhereOrNull((EpubManifestItem item) =>
            item.id!.toLowerCase() == tocId.toLowerCase());
    if (tocManifestItem == null) {
      throw EpubUnresolvedReferenceException(
          'EPUB parsing error: TOC item $tocId not found in EPUB manifest.');
    }

    final ArchiveFile tocFileEntry = _readTocFileEntry(epubArchive,
        _pathResolver.combine(contentDirectoryPath, tocManifestItem.href));
    final xml.XmlDocument containerDocument =
        xml.XmlDocument.parse(convert.utf8.decode(tocFileEntry.content));
    return _requireElement(
        containerDocument.findAllElements('ncx', namespace: _ncxNamespace),
        element: 'ncx',
        document: 'TOC file');
  }

  /// The EPUB3 table of contents: an XHTML nav document flagged
  /// `properties="nav"` in the manifest.
  EpubNavigation _readEpub3Navigation(
      Archive epubArchive, String contentDirectoryPath, EpubPackage package) {
    final EpubManifestItem? tocManifestItem = package.manifest!.items!
        .firstWhereOrNull((EpubManifestItem item) => item.properties == 'nav');
    if (tocManifestItem == null) {
      throw const EpubUnresolvedReferenceException(
          'EPUB parsing error: TOC item, not found in EPUB manifest.');
    }

    final ArchiveFile tocFileEntry = _readTocFileEntry(epubArchive,
        _pathResolver.combine(contentDirectoryPath, tocManifestItem.href));
    final String navBase = _navBaseOf(tocManifestItem.href!);
    final xml.XmlDocument containerDocument =
        xml.XmlDocument.parse(convert.utf8.decode(tocFileEntry.content));

    _requireElement(containerDocument.findAllElements('head'),
        element: 'head', document: 'TOC file');

    final EpubNavigation result = EpubNavigation();
    result.docTitle = EpubNavigationDocTitle()
      ..titles = package.metadata!.titles;
    result.docAuthors = <EpubNavigationDocAuthor>[];

    final xml.XmlElement navNode = _requireElement(
        containerDocument.findAllElements('nav'),
        element: 'nav',
        document: 'TOC file');
    result.navMap =
        readNavigationMapV3(navNode.findElements('ol').single, navBase);
    // EPUB3 page lists are not read: nothing downstream consumes one, and the
    // EPUB2 pageList above is where the reader's page targets come from.
    return result;
  }

  /// Base for resolving nav-internal relative links. `content.*` is keyed by
  /// the raw manifest href, so the base is the nav item's own href directory.
  /// Stripping a leading path segment instead would assume the OPF lives
  /// inside a content folder - false when it sits at the archive root, and
  /// there the real content folder gets eaten.
  String _navBaseOf(String tocManifestItemHref) {
    final String navDirectory =
        _pathResolver.getDirectoryPath(tocManifestItemHref);
    return navDirectory.isEmpty ? '' : '$navDirectory/';
  }

  ArchiveFile _readTocFileEntry(Archive epubArchive, String? tocFileEntryPath) {
    final ArchiveFile? tocFileEntry = epubArchive.files.firstWhereOrNull(
        (ArchiveFile file) =>
            file.name.toLowerCase() == tocFileEntryPath!.toLowerCase());
    if (tocFileEntry == null) {
      throw EpubMissingArchiveEntryException(
          'EPUB parsing error: TOC file $tocFileEntryPath not found in archive.');
    }
    return tocFileEntry;
  }

  /// The first of [elements], or a refusal naming what [document] was missing.
  xml.XmlElement _requireElement(Iterable<xml.XmlElement> elements,
      {required String element, required String document}) {
    final xml.XmlElement? found = elements.firstOrNull;
    if (found == null) {
      throw EpubMissingElementException(
          'EPUB parsing error: $document does not contain $element element.');
    }
    return found;
  }

  EpubNavigationContent readNavigationContent(
      xml.XmlElement navigationContentNode) {
    final EpubNavigationContent result = EpubNavigationContent();
    for (xml.XmlAttribute navigationContentNodeAttribute
        in navigationContentNode.attributes) {
      _applyNavigationContentAttribute(result, navigationContentNodeAttribute);
    }
    if (result.source == null || result.source!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation content: content source is missing.');
    }

    return result;
  }

  void _applyNavigationContentAttribute(
      EpubNavigationContent result, xml.XmlAttribute attribute) {
    final String attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.id = attributeValue;
        break;
      case 'src':
        result.source = attributeValue;
        break;
    }
  }

  EpubNavigationContent readNavigationContentV3(
      xml.XmlElement navigationContentNode, String navBase) {
    final EpubNavigationContent result = EpubNavigationContent();
    for (xml.XmlAttribute navigationContentNodeAttribute
        in navigationContentNode.attributes) {
      _applyNavigationContentV3Attribute(
          result, navigationContentNodeAttribute, navBase);
    }
    // An `<li>` carrying a `<span>` rather than an `<a>` has no href at all,
    // which is legal in a nav document - so, unlike EPUB2, a null source here
    // is not a parsing error.
    return result;
  }

  void _applyNavigationContentV3Attribute(EpubNavigationContent result,
      xml.XmlAttribute attribute, String navBase) {
    final String attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.id = attributeValue;
        break;
      case 'href':
        result.source = navBase.isEmpty || attributeValue.startsWith(navBase)
            ? attributeValue
            : path.normalize(navBase + attributeValue);
        break;
    }
  }

  String extractContentPath(String tocFileEntryPath, String ref) {
    final String normalizedTocFileEntryPath = tocFileEntryPath.endsWith('/')
        ? tocFileEntryPath
        : '$tocFileEntryPath/';
    String r = normalizedTocFileEntryPath + ref;
    r = r.replaceAll('/./', '/');
    r = r.replaceAll(RegExp(r'/[^/]+/\.\./'), '/');
    r = r.replaceAll(RegExp(r'^[^/]+/\.\./'), '');
    return r;
  }

  EpubNavigationDocAuthor readNavigationDocAuthor(
      xml.XmlElement docAuthorNode) {
    final EpubNavigationDocAuthor result = EpubNavigationDocAuthor();
    result.authors = <String>[];
    docAuthorNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement textNode) {
      if (textNode.name.local.toLowerCase() == 'text') {
        result.authors!.add(textNode.innerText);
      }
    });
    return result;
  }

  EpubNavigationDocTitle readNavigationDocTitle(xml.XmlElement docTitleNode) {
    final EpubNavigationDocTitle result = EpubNavigationDocTitle();
    result.titles = <String>[];
    docTitleNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement textNode) {
      if (textNode.name.local.toLowerCase() == 'text') {
        result.titles!.add(textNode.innerText);
      }
    });
    return result;
  }

  EpubNavigationHead readNavigationHead(xml.XmlElement headNode) {
    final EpubNavigationHead result = EpubNavigationHead();
    result.metadata = <EpubNavigationHeadMeta>[];

    headNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement metaNode) {
      if (metaNode.name.local.toLowerCase() == 'meta') {
        result.metadata!.add(_readNavigationHeadMeta(metaNode));
      }
    });
    return result;
  }

  EpubNavigationHeadMeta _readNavigationHeadMeta(xml.XmlElement metaNode) {
    final EpubNavigationHeadMeta meta = EpubNavigationHeadMeta();
    for (xml.XmlAttribute metaNodeAttribute in metaNode.attributes) {
      _applyNavigationHeadMetaAttribute(meta, metaNodeAttribute);
    }

    if (meta.name == null || meta.name!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation meta: meta name is missing.');
    }
    if (meta.content == null) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation meta: meta content is missing.');
    }
    return meta;
  }

  void _applyNavigationHeadMetaAttribute(
      EpubNavigationHeadMeta meta, xml.XmlAttribute attribute) {
    final String attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'name':
        meta.name = attributeValue;
        break;
      case 'content':
        meta.content = attributeValue;
        break;
      case 'scheme':
        meta.scheme = attributeValue;
        break;
    }
  }

  EpubNavigationLabel readNavigationLabel(xml.XmlElement navigationLabelNode) {
    final EpubNavigationLabel result = EpubNavigationLabel();

    final xml.XmlElement? navigationLabelTextNode = navigationLabelNode
        .findElements('text', namespace: navigationLabelNode.name.namespaceUri)
        .firstOrNull;
    if (navigationLabelTextNode == null) {
      throw const EpubMissingElementException(
          'Incorrect EPUB navigation label: label text element is missing.');
    }

    result.text = navigationLabelTextNode.innerText;

    return result;
  }

  EpubNavigationLabel readNavigationLabelV3(
      xml.XmlElement navigationLabelNode) {
    final EpubNavigationLabel result = EpubNavigationLabel();
    result.text = navigationLabelNode.innerText.trim();
    return result;
  }

  EpubNavigationList readNavigationList(xml.XmlElement navigationListNode) {
    final EpubNavigationList result = EpubNavigationList();
    for (xml.XmlAttribute navigationListNodeAttribute
        in navigationListNode.attributes) {
      _applyNavigationListAttribute(result, navigationListNodeAttribute);
    }
    navigationListNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationListChildNode) {
      switch (navigationListChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          final EpubNavigationLabel navigationLabel =
              readNavigationLabel(navigationListChildNode);
          result.navigationLabels!.add(navigationLabel);
          break;
        case 'navtarget':
          final EpubNavigationTarget navigationTarget =
              readNavigationTarget(navigationListChildNode);
          result.navigationTargets!.add(navigationTarget);
          break;
      }
    });
    // No "at least one navLabel" guard here: `EpubNavigationList` leaves both
    // of those lists null, so a navList carrying either child fails on the
    // append above long before a guard could run.
    return result;
  }

  void _applyNavigationListAttribute(
      EpubNavigationList result, xml.XmlAttribute attribute) {
    final String attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.id = attributeValue;
        break;
      case 'class':
        result.className = attributeValue;
        break;
    }
  }

  EpubNavigationMap readNavigationMap(xml.XmlElement navigationMapNode) {
    final EpubNavigationMap result = EpubNavigationMap();
    result.points = <EpubNavigationPoint>[];
    navigationMapNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPointNode) {
      if (navigationPointNode.name.local.toLowerCase() == 'navpoint') {
        final EpubNavigationPoint navigationPoint =
            readNavigationPoint(navigationPointNode);
        result.points!.add(navigationPoint);
      }
    });
    return result;
  }

  EpubNavigationMap readNavigationMapV3(
      xml.XmlElement navigationMapNode, String navBase) {
    final EpubNavigationMap result = EpubNavigationMap();
    result.points = <EpubNavigationPoint>[];
    navigationMapNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPointNode) {
      if (navigationPointNode.name.local.toLowerCase() == 'li') {
        final EpubNavigationPoint navigationPoint =
            readNavigationPointV3(navigationPointNode, navBase);
        result.points!.add(navigationPoint);
      }
    });
    return result;
  }

  EpubNavigationPageList readNavigationPageList(
      xml.XmlElement navigationPageListNode) {
    final EpubNavigationPageList result = EpubNavigationPageList();
    result.targets = <EpubNavigationPageTarget>[];
    navigationPageListNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement pageTargetNode) {
      if (pageTargetNode.name.local == 'pageTarget') {
        final EpubNavigationPageTarget pageTarget =
            readNavigationPageTarget(pageTargetNode);
        result.targets!.add(pageTarget);
      }
    });

    return result;
  }

  EpubNavigationPageTarget readNavigationPageTarget(
      xml.XmlElement navigationPageTargetNode) {
    final EpubNavigationPageTarget result = EpubNavigationPageTarget();
    result.navigationLabels = <EpubNavigationLabel>[];
    for (xml.XmlAttribute navigationPageTargetNodeAttribute
        in navigationPageTargetNode.attributes) {
      _applyNavigationPageTargetAttribute(
          result, navigationPageTargetNodeAttribute);
    }
    if (result.type == EpubNavigationPageTargetType.undefined) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation page target: page target type is missing.');
    }

    navigationPageTargetNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPageTargetChildNode) {
      switch (navigationPageTargetChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          final EpubNavigationLabel navigationLabel =
              readNavigationLabel(navigationPageTargetChildNode);
          result.navigationLabels!.add(navigationLabel);
          break;
        case 'content':
          final EpubNavigationContent content =
              readNavigationContent(navigationPageTargetChildNode);
          result.content = content;
          break;
      }
    });
    if (result.navigationLabels!.isEmpty) {
      throw const EpubMissingElementException(
          'Incorrect EPUB navigation page target: at least one navLabel element is required.');
    }

    return result;
  }

  void _applyNavigationPageTargetAttribute(
      EpubNavigationPageTarget result, xml.XmlAttribute attribute) {
    final String attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.id = attributeValue;
        break;
      case 'value':
        result.value = attributeValue;
        break;
      case 'type':
        result.type = EnumFromString<EpubNavigationPageTargetType>(
                EpubNavigationPageTargetType.values)
            .get(attributeValue);
        break;
      case 'class':
        result.className = attributeValue;
        break;
      case 'playorder':
        result.playOrder = attributeValue;
        break;
    }
  }

  EpubNavigationPoint readNavigationPoint(xml.XmlElement navigationPointNode) {
    final EpubNavigationPoint result = EpubNavigationPoint();
    for (xml.XmlAttribute navigationPointNodeAttribute
        in navigationPointNode.attributes) {
      _applyNavigationPointAttribute(result, navigationPointNodeAttribute);
    }
    if (result.id == null || result.id!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation point: point ID is missing.');
    }

    result.navigationLabels = <EpubNavigationLabel>[];
    result.childNavigationPoints = <EpubNavigationPoint>[];
    navigationPointNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPointChildNode) {
      switch (navigationPointChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          final EpubNavigationLabel navigationLabel =
              readNavigationLabel(navigationPointChildNode);
          result.navigationLabels!.add(navigationLabel);
          break;
        case 'content':
          final EpubNavigationContent content =
              readNavigationContent(navigationPointChildNode);
          result.content = content;
          break;
        case 'navpoint':
          final EpubNavigationPoint childNavigationPoint =
              readNavigationPoint(navigationPointChildNode);
          result.childNavigationPoints!.add(childNavigationPoint);
          break;
      }
    });

    _requireNavigationPointChildren(result);
    return result;
  }

  void _applyNavigationPointAttribute(
      EpubNavigationPoint result, xml.XmlAttribute attribute) {
    final String attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.id = attributeValue;
        break;
      case 'class':
        result.className = attributeValue;
        break;
      case 'playorder':
        result.playOrder = attributeValue;
        break;
    }
  }

  /// A navigation point with no label has nothing to show, and one with no
  /// content has nowhere to go; EPUB2 and EPUB3 refuse both shapes alike.
  void _requireNavigationPointChildren(EpubNavigationPoint result) {
    if (result.navigationLabels!.isEmpty) {
      throw EpubMissingElementException(
          'EPUB parsing error: navigation point ${result.id} should contain at least one navigation label.');
    }
    if (result.content == null) {
      throw EpubMissingElementException(
          'EPUB parsing error: navigation point ${result.id} should contain content.');
    }
  }

  EpubNavigationPoint readNavigationPointV3(
      xml.XmlElement navigationPointNode, String navBase) {
    final EpubNavigationPoint result = EpubNavigationPoint();

    result.navigationLabels = <EpubNavigationLabel>[];
    result.childNavigationPoints = <EpubNavigationPoint>[];
    navigationPointNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPointChildNode) {
      switch (navigationPointChildNode.name.local.toLowerCase()) {
        case 'a':
        case 'span':
          final EpubNavigationLabel navigationLabel =
              readNavigationLabelV3(navigationPointChildNode);
          result.navigationLabels!.add(navigationLabel);
          final EpubNavigationContent content =
              readNavigationContentV3(navigationPointChildNode, navBase);
          result.content = content;
          break;
        case 'ol':
          readNavigationMapV3(navigationPointChildNode, navBase)
              .points!
              .forEach(result.childNavigationPoints!.add);
          break;
      }
    });

    _requireNavigationPointChildren(result);
    return result;
  }

  EpubNavigationTarget readNavigationTarget(
      xml.XmlElement navigationTargetNode) {
    final EpubNavigationTarget result = EpubNavigationTarget();
    for (xml.XmlAttribute navigationPageTargetNodeAttribute
        in navigationTargetNode.attributes) {
      _applyNavigationTargetAttribute(
          result, navigationPageTargetNodeAttribute);
    }
    if (result.id == null || result.id!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation target: navigation target ID is missing.');
    }

    navigationTargetNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationTargetChildNode) {
      switch (navigationTargetChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          final EpubNavigationLabel navigationLabel =
              readNavigationLabel(navigationTargetChildNode);
          result.navigationLabels!.add(navigationLabel);
          break;
        case 'content':
          final EpubNavigationContent content =
              readNavigationContent(navigationTargetChildNode);
          result.content = content;
          break;
      }
    });
    if (result.navigationLabels!.isEmpty) {
      throw const EpubMissingElementException(
          'Incorrect EPUB navigation target: at least one navLabel element is required.');
    }

    return result;
  }

  void _applyNavigationTargetAttribute(
      EpubNavigationTarget result, xml.XmlAttribute attribute) {
    final String attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.id = attributeValue;
        break;
      case 'value':
        result.value = attributeValue;
        break;
      case 'class':
        result.className = attributeValue;
        break;
      case 'playorder':
        result.playOrder = attributeValue;
        break;
    }
  }
}
