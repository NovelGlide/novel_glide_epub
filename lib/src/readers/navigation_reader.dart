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

  final ZipPathResolver _pathResolver = const ZipPathResolver();

  Future<EpubNavigation> readNavigation(Archive epubArchive,
      String contentDirectoryPath, EpubPackage package) async {
    if (package.Version == EpubVersion.Epub2) {
      return _readEpub2Navigation(epubArchive, contentDirectoryPath, package);
    }
    return _readEpub3Navigation(epubArchive, contentDirectoryPath, package);
  }

  /// The EPUB2 table of contents: an NCX document named by the spine's `toc`
  /// attribute.
  EpubNavigation _readEpub2Navigation(
      Archive epubArchive, String contentDirectoryPath, EpubPackage package) {
    var ncxNode = _readNcxElement(epubArchive, contentDirectoryPath, package);
    var result = EpubNavigation();

    result.Head = readNavigationHead(_requireElement(
        ncxNode.findAllElements('head', namespace: _ncxNamespace),
        element: 'head',
        document: 'TOC file'));
    result.DocTitle = readNavigationDocTitle(_requireElement(
        ncxNode.findElements('docTitle', namespace: _ncxNamespace),
        element: 'docTitle',
        document: 'TOC file'));
    result.DocAuthors = ncxNode
        .findElements('docAuthor', namespace: _ncxNamespace)
        .map(readNavigationDocAuthor)
        .toList();
    result.NavMap = readNavigationMap(_requireElement(
        ncxNode.findElements('navMap', namespace: _ncxNamespace),
        element: 'navMap',
        document: 'TOC file'));

    // A pageList is optional, so its absence is not a parsing error.
    var pageListNode =
        ncxNode.findElements('pageList', namespace: _ncxNamespace).firstOrNull;
    if (pageListNode != null) {
      result.PageList = readNavigationPageList(pageListNode);
    }

    result.NavLists = ncxNode
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
    var tocId = package.Spine!.TableOfContents;
    if (tocId == null || tocId.isEmpty) {
      throw const EpubMissingValueException(
          'EPUB parsing error: TOC ID is empty.');
    }

    var tocManifestItem = package.Manifest!.Items!.firstWhereOrNull(
        (EpubManifestItem item) =>
            item.Id!.toLowerCase() == tocId.toLowerCase());
    if (tocManifestItem == null) {
      throw EpubUnresolvedReferenceException(
          'EPUB parsing error: TOC item $tocId not found in EPUB manifest.');
    }

    var tocFileEntry = _readTocFileEntry(epubArchive,
        _pathResolver.combine(contentDirectoryPath, tocManifestItem.Href));
    var containerDocument =
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
    var tocManifestItem = package.Manifest!.Items!
        .firstWhereOrNull((EpubManifestItem item) => item.Properties == 'nav');
    if (tocManifestItem == null) {
      throw const EpubUnresolvedReferenceException(
          'EPUB parsing error: TOC item, not found in EPUB manifest.');
    }

    var tocFileEntry = _readTocFileEntry(epubArchive,
        _pathResolver.combine(contentDirectoryPath, tocManifestItem.Href));
    var navBase = _navBaseOf(tocManifestItem.Href!);
    var containerDocument =
        xml.XmlDocument.parse(convert.utf8.decode(tocFileEntry.content));

    _requireElement(containerDocument.findAllElements('head'),
        element: 'head', document: 'TOC file');

    var result = EpubNavigation();
    result.DocTitle = EpubNavigationDocTitle()
      ..Titles = package.Metadata!.Titles;
    result.DocAuthors = <EpubNavigationDocAuthor>[];

    var navNode = _requireElement(containerDocument.findAllElements('nav'),
        element: 'nav', document: 'TOC file');
    result.NavMap =
        readNavigationMapV3(navNode.findElements('ol').single, navBase);
    // EPUB3 page lists are not read: nothing downstream consumes one, and the
    // EPUB2 pageList above is where the reader's page targets come from.
    return result;
  }

  /// Base for resolving nav-internal relative links. `Content.*` is keyed by
  /// the raw manifest href, so the base is the nav item's own href directory.
  /// Stripping a leading path segment instead would assume the OPF lives
  /// inside a content folder - false when it sits at the archive root, and
  /// there the real content folder gets eaten.
  String _navBaseOf(String tocManifestItemHref) {
    var navDirectory = _pathResolver.getDirectoryPath(tocManifestItemHref);
    return navDirectory.isEmpty ? '' : '$navDirectory/';
  }

  ArchiveFile _readTocFileEntry(Archive epubArchive, String? tocFileEntryPath) {
    var tocFileEntry = epubArchive.files.firstWhereOrNull((ArchiveFile file) =>
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
    var found = elements.firstOrNull;
    if (found == null) {
      throw EpubMissingElementException(
          'EPUB parsing error: $document does not contain $element element.');
    }
    return found;
  }

  EpubNavigationContent readNavigationContent(
      xml.XmlElement navigationContentNode) {
    var result = EpubNavigationContent();
    for (var navigationContentNodeAttribute
        in navigationContentNode.attributes) {
      _applyNavigationContentAttribute(result, navigationContentNodeAttribute);
    }
    if (result.Source == null || result.Source!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation content: content source is missing.');
    }

    return result;
  }

  void _applyNavigationContentAttribute(
      EpubNavigationContent result, xml.XmlAttribute attribute) {
    var attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.Id = attributeValue;
        break;
      case 'src':
        result.Source = attributeValue;
        break;
    }
  }

  EpubNavigationContent readNavigationContentV3(
      xml.XmlElement navigationContentNode, String navBase) {
    var result = EpubNavigationContent();
    for (var navigationContentNodeAttribute
        in navigationContentNode.attributes) {
      _applyNavigationContentV3Attribute(
          result, navigationContentNodeAttribute, navBase);
    }
    // An `<li>` carrying a `<span>` rather than an `<a>` has no href at all,
    // which is legal in a nav document - so, unlike EPUB2, a null Source here
    // is not a parsing error.
    return result;
  }

  void _applyNavigationContentV3Attribute(EpubNavigationContent result,
      xml.XmlAttribute attribute, String navBase) {
    var attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.Id = attributeValue;
        break;
      case 'href':
        result.Source = navBase.isEmpty || attributeValue.startsWith(navBase)
            ? attributeValue
            : path.normalize(navBase + attributeValue);
        break;
    }
  }

  String extractContentPath(String tocFileEntryPath, String ref) {
    if (!tocFileEntryPath.endsWith('/')) {
      tocFileEntryPath = '$tocFileEntryPath/';
    }
    var r = tocFileEntryPath + ref;
    r = r.replaceAll('/./', '/');
    r = r.replaceAll(RegExp(r'/[^/]+/\.\./'), '/');
    r = r.replaceAll(RegExp(r'^[^/]+/\.\./'), '');
    return r;
  }

  EpubNavigationDocAuthor readNavigationDocAuthor(
      xml.XmlElement docAuthorNode) {
    var result = EpubNavigationDocAuthor();
    result.Authors = <String>[];
    docAuthorNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement textNode) {
      if (textNode.name.local.toLowerCase() == 'text') {
        result.Authors!.add(textNode.text);
      }
    });
    return result;
  }

  EpubNavigationDocTitle readNavigationDocTitle(xml.XmlElement docTitleNode) {
    var result = EpubNavigationDocTitle();
    result.Titles = <String>[];
    docTitleNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement textNode) {
      if (textNode.name.local.toLowerCase() == 'text') {
        result.Titles!.add(textNode.text);
      }
    });
    return result;
  }

  EpubNavigationHead readNavigationHead(xml.XmlElement headNode) {
    var result = EpubNavigationHead();
    result.Metadata = <EpubNavigationHeadMeta>[];

    headNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement metaNode) {
      if (metaNode.name.local.toLowerCase() == 'meta') {
        result.Metadata!.add(_readNavigationHeadMeta(metaNode));
      }
    });
    return result;
  }

  EpubNavigationHeadMeta _readNavigationHeadMeta(xml.XmlElement metaNode) {
    var meta = EpubNavigationHeadMeta();
    for (var metaNodeAttribute in metaNode.attributes) {
      _applyNavigationHeadMetaAttribute(meta, metaNodeAttribute);
    }

    if (meta.Name == null || meta.Name!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation meta: meta name is missing.');
    }
    if (meta.Content == null) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation meta: meta content is missing.');
    }
    return meta;
  }

  void _applyNavigationHeadMetaAttribute(
      EpubNavigationHeadMeta meta, xml.XmlAttribute attribute) {
    var attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'name':
        meta.Name = attributeValue;
        break;
      case 'content':
        meta.Content = attributeValue;
        break;
      case 'scheme':
        meta.Scheme = attributeValue;
        break;
    }
  }

  EpubNavigationLabel readNavigationLabel(xml.XmlElement navigationLabelNode) {
    var result = EpubNavigationLabel();

    var navigationLabelTextNode = navigationLabelNode
        .findElements('text', namespace: navigationLabelNode.name.namespaceUri)
        .firstOrNull;
    if (navigationLabelTextNode == null) {
      throw const EpubMissingElementException(
          'Incorrect EPUB navigation label: label text element is missing.');
    }

    result.Text = navigationLabelTextNode.text;

    return result;
  }

  EpubNavigationLabel readNavigationLabelV3(
      xml.XmlElement navigationLabelNode) {
    var result = EpubNavigationLabel();
    result.Text = navigationLabelNode.text.trim();
    return result;
  }

  EpubNavigationList readNavigationList(xml.XmlElement navigationListNode) {
    var result = EpubNavigationList();
    for (var navigationListNodeAttribute in navigationListNode.attributes) {
      _applyNavigationListAttribute(result, navigationListNodeAttribute);
    }
    navigationListNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationListChildNode) {
      switch (navigationListChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          var navigationLabel = readNavigationLabel(navigationListChildNode);
          result.NavigationLabels!.add(navigationLabel);
          break;
        case 'navtarget':
          var navigationTarget = readNavigationTarget(navigationListChildNode);
          result.NavigationTargets!.add(navigationTarget);
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
    var attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.Id = attributeValue;
        break;
      case 'class':
        result.Class = attributeValue;
        break;
    }
  }

  EpubNavigationMap readNavigationMap(xml.XmlElement navigationMapNode) {
    var result = EpubNavigationMap();
    result.Points = <EpubNavigationPoint>[];
    navigationMapNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPointNode) {
      if (navigationPointNode.name.local.toLowerCase() == 'navpoint') {
        var navigationPoint = readNavigationPoint(navigationPointNode);
        result.Points!.add(navigationPoint);
      }
    });
    return result;
  }

  EpubNavigationMap readNavigationMapV3(
      xml.XmlElement navigationMapNode, String navBase) {
    var result = EpubNavigationMap();
    result.Points = <EpubNavigationPoint>[];
    navigationMapNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPointNode) {
      if (navigationPointNode.name.local.toLowerCase() == 'li') {
        var navigationPoint =
            readNavigationPointV3(navigationPointNode, navBase);
        result.Points!.add(navigationPoint);
      }
    });
    return result;
  }

  EpubNavigationPageList readNavigationPageList(
      xml.XmlElement navigationPageListNode) {
    var result = EpubNavigationPageList();
    result.Targets = <EpubNavigationPageTarget>[];
    navigationPageListNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement pageTargetNode) {
      if (pageTargetNode.name.local == 'pageTarget') {
        var pageTarget = readNavigationPageTarget(pageTargetNode);
        result.Targets!.add(pageTarget);
      }
    });

    return result;
  }

  EpubNavigationPageTarget readNavigationPageTarget(
      xml.XmlElement navigationPageTargetNode) {
    var result = EpubNavigationPageTarget();
    result.NavigationLabels = <EpubNavigationLabel>[];
    for (var navigationPageTargetNodeAttribute
        in navigationPageTargetNode.attributes) {
      _applyNavigationPageTargetAttribute(
          result, navigationPageTargetNodeAttribute);
    }
    if (result.Type == EpubNavigationPageTargetType.UNDEFINED) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation page target: page target type is missing.');
    }

    navigationPageTargetNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPageTargetChildNode) {
      switch (navigationPageTargetChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          var navigationLabel =
              readNavigationLabel(navigationPageTargetChildNode);
          result.NavigationLabels!.add(navigationLabel);
          break;
        case 'content':
          var content = readNavigationContent(navigationPageTargetChildNode);
          result.Content = content;
          break;
      }
    });
    if (result.NavigationLabels!.isEmpty) {
      throw const EpubMissingElementException(
          'Incorrect EPUB navigation page target: at least one navLabel element is required.');
    }

    return result;
  }

  void _applyNavigationPageTargetAttribute(
      EpubNavigationPageTarget result, xml.XmlAttribute attribute) {
    var attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.Id = attributeValue;
        break;
      case 'value':
        result.Value = attributeValue;
        break;
      case 'type':
        result.Type = EnumFromString<EpubNavigationPageTargetType>(
                EpubNavigationPageTargetType.values)
            .get(attributeValue);
        break;
      case 'class':
        result.Class = attributeValue;
        break;
      case 'playorder':
        result.PlayOrder = attributeValue;
        break;
    }
  }

  EpubNavigationPoint readNavigationPoint(xml.XmlElement navigationPointNode) {
    var result = EpubNavigationPoint();
    for (var navigationPointNodeAttribute in navigationPointNode.attributes) {
      _applyNavigationPointAttribute(result, navigationPointNodeAttribute);
    }
    if (result.Id == null || result.Id!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation point: point ID is missing.');
    }

    result.NavigationLabels = <EpubNavigationLabel>[];
    result.ChildNavigationPoints = <EpubNavigationPoint>[];
    navigationPointNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPointChildNode) {
      switch (navigationPointChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          var navigationLabel = readNavigationLabel(navigationPointChildNode);
          result.NavigationLabels!.add(navigationLabel);
          break;
        case 'content':
          var content = readNavigationContent(navigationPointChildNode);
          result.Content = content;
          break;
        case 'navpoint':
          var childNavigationPoint =
              readNavigationPoint(navigationPointChildNode);
          result.ChildNavigationPoints!.add(childNavigationPoint);
          break;
      }
    });

    _requireNavigationPointChildren(result);
    return result;
  }

  void _applyNavigationPointAttribute(
      EpubNavigationPoint result, xml.XmlAttribute attribute) {
    var attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.Id = attributeValue;
        break;
      case 'class':
        result.Class = attributeValue;
        break;
      case 'playorder':
        result.PlayOrder = attributeValue;
        break;
    }
  }

  /// A navigation point with no label has nothing to show, and one with no
  /// content has nowhere to go; EPUB2 and EPUB3 refuse both shapes alike.
  void _requireNavigationPointChildren(EpubNavigationPoint result) {
    if (result.NavigationLabels!.isEmpty) {
      throw EpubMissingElementException(
          'EPUB parsing error: navigation point ${result.Id} should contain at least one navigation label.');
    }
    if (result.Content == null) {
      throw EpubMissingElementException(
          'EPUB parsing error: navigation point ${result.Id} should contain content.');
    }
  }

  EpubNavigationPoint readNavigationPointV3(
      xml.XmlElement navigationPointNode, String navBase) {
    var result = EpubNavigationPoint();

    result.NavigationLabels = <EpubNavigationLabel>[];
    result.ChildNavigationPoints = <EpubNavigationPoint>[];
    navigationPointNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationPointChildNode) {
      switch (navigationPointChildNode.name.local.toLowerCase()) {
        case 'a':
        case 'span':
          var navigationLabel = readNavigationLabelV3(navigationPointChildNode);
          result.NavigationLabels!.add(navigationLabel);
          var content =
              readNavigationContentV3(navigationPointChildNode, navBase);
          result.Content = content;
          break;
        case 'ol':
          for (var point
              in readNavigationMapV3(navigationPointChildNode, navBase)
                  .Points!) {
            result.ChildNavigationPoints!.add(point);
          }
          break;
      }
    });

    _requireNavigationPointChildren(result);
    return result;
  }

  EpubNavigationTarget readNavigationTarget(
      xml.XmlElement navigationTargetNode) {
    var result = EpubNavigationTarget();
    for (var navigationPageTargetNodeAttribute
        in navigationTargetNode.attributes) {
      _applyNavigationTargetAttribute(
          result, navigationPageTargetNodeAttribute);
    }
    if (result.Id == null || result.Id!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation target: navigation target ID is missing.');
    }

    navigationTargetNode.children
        .whereType<xml.XmlElement>()
        .forEach((xml.XmlElement navigationTargetChildNode) {
      switch (navigationTargetChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          var navigationLabel = readNavigationLabel(navigationTargetChildNode);
          result.NavigationLabels!.add(navigationLabel);
          break;
        case 'content':
          var content = readNavigationContent(navigationTargetChildNode);
          result.Content = content;
          break;
      }
    });
    if (result.NavigationLabels!.isEmpty) {
      throw const EpubMissingElementException(
          'Incorrect EPUB navigation target: at least one navLabel element is required.');
    }

    return result;
  }

  void _applyNavigationTargetAttribute(
      EpubNavigationTarget result, xml.XmlAttribute attribute) {
    var attributeValue = attribute.value;
    switch (attribute.name.local.toLowerCase()) {
      case 'id':
        result.Id = attributeValue;
        break;
      case 'value':
        result.Value = attributeValue;
        break;
      case 'class':
        result.Class = attributeValue;
        break;
      case 'playorder':
        result.PlayOrder = attributeValue;
        break;
    }
  }
}
