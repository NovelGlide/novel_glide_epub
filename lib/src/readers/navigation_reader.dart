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
import '../utils/unmodifiable_iterable.dart';
import '../utils/xml_attribute_reader.dart';
import '../utils/zip_path_resolver.dart';

class NavigationReader {
  const NavigationReader();

  static const String _ncxNamespace = 'http://www.daisy.org/z3986/2005/ncx/';

  ZipPathResolver get _pathResolver => const ZipPathResolver();
  XmlAttributeReader get _attributes => const XmlAttributeReader();

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

    final EpubNavigationHead head = readNavigationHead(_requireElement(
        ncxNode.findAllElements('head', namespace: _ncxNamespace),
        element: 'head',
        document: 'TOC file'));
    final EpubNavigationDocTitle docTitle = readNavigationDocTitle(
        _requireElement(
            ncxNode.findElements('docTitle', namespace: _ncxNamespace),
            element: 'docTitle',
            document: 'TOC file'));
    final List<EpubNavigationDocAuthor> docAuthors = ncxNode
        .findElements('docAuthor', namespace: _ncxNamespace)
        .map(readNavigationDocAuthor)
        .toUnmodifiableList();
    final EpubNavigationMap navMap = readNavigationMap(_requireElement(
        ncxNode.findElements('navMap', namespace: _ncxNamespace),
        element: 'navMap',
        document: 'TOC file'));
    final xml.XmlElement? pageListNode =
        ncxNode.findElements('pageList', namespace: _ncxNamespace).firstOrNull;

    return EpubNavigation(
      head: head,
      docTitle: docTitle,
      docAuthors: docAuthors,
      navMap: navMap,
      pageList:
          pageListNode == null ? null : readNavigationPageList(pageListNode),
      navLists: ncxNode
          .findElements('navList', namespace: _ncxNamespace)
          .map(readNavigationList)
          .toUnmodifiableList(),
    );
  }

  /// Walks spine `toc` attribute -> manifest item -> archive entry -> the
  /// `ncx` root element, refusing the book at whichever step first comes up
  /// empty.
  xml.XmlElement _readNcxElement(
      Archive epubArchive, String contentDirectoryPath, EpubPackage package) {
    final String? tocId = package.spine.tableOfContents;
    if (tocId == null || tocId.isEmpty) {
      throw const EpubMissingValueException(
          'EPUB parsing error: TOC ID is empty.');
    }

    final EpubManifestItem? tocManifestItem = package.manifest.items
        .firstWhereOrNull((EpubManifestItem item) =>
            item.id.toLowerCase() == tocId.toLowerCase());
    if (tocManifestItem == null) {
      throw EpubUnresolvedReferenceException(
          'EPUB parsing error: TOC item $tocId not found in EPUB manifest.');
    }

    final ArchiveFile tocFileEntry = _readTocFileEntry(
        epubArchive,
        _pathResolver.combine(contentDirectoryPath,
            _pathResolver.decodeHref(tocManifestItem.href)));
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
    final EpubManifestItem? tocManifestItem = package.manifest.items
        .firstWhereOrNull((EpubManifestItem item) => item.properties == 'nav');
    if (tocManifestItem == null) {
      throw const EpubUnresolvedReferenceException(
          'EPUB parsing error: TOC item, not found in EPUB manifest.');
    }

    final ArchiveFile tocFileEntry = _readTocFileEntry(
        epubArchive,
        _pathResolver.combine(contentDirectoryPath,
            _pathResolver.decodeHref(tocManifestItem.href)));
    final String navBase = _navBaseOf(tocManifestItem.href);
    final xml.XmlDocument containerDocument =
        xml.XmlDocument.parse(convert.utf8.decode(tocFileEntry.content));

    _requireElement(containerDocument.findAllElements('head'),
        element: 'head', document: 'TOC file');

    final xml.XmlElement navNode = _requireElement(
        containerDocument.findAllElements('nav'),
        element: 'nav',
        document: 'TOC file');
    // EPUB3 page lists are not read: nothing downstream consumes one, and the
    // EPUB2 pageList above is where the reader's page targets come from.
    return EpubNavigation(
      head: const EpubNavigationHead(metadata: <EpubNavigationHeadMeta>[]),
      docTitle: EpubNavigationDocTitle(titles: package.metadata.titles),
      navMap: readNavigationMapV3(navNode.findElements('ol').single, navBase),
    );
  }

  /// Base for resolving nav-internal relative links: the nav item's own href
  /// directory, as the manifest wrote it. Stripping a leading path segment
  /// instead would assume the OPF lives inside a content folder - false when
  /// it sits at the archive root, and there the real content folder gets
  /// eaten.
  String _navBaseOf(String tocManifestItemHref) {
    final String navDirectory =
        _pathResolver.getDirectoryPath(tocManifestItemHref);
    return navDirectory.isEmpty ? '' : '$navDirectory/';
  }

  ArchiveFile _readTocFileEntry(Archive epubArchive, String tocFileEntryPath) {
    final ArchiveFile? tocFileEntry = epubArchive.files.firstWhereOrNull(
        (ArchiveFile file) =>
            file.name.toLowerCase() == tocFileEntryPath.toLowerCase());
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

  /// The children of [parent] whose lower-cased local name is [localName].
  Iterable<xml.XmlElement> _childrenNamed(
          xml.XmlElement parent, String localName) =>
      parent.children.whereType<xml.XmlElement>().where(
          (xml.XmlElement child) =>
              child.name.local.toLowerCase() == localName);

  EpubNavigationContent readNavigationContent(
      xml.XmlElement navigationContentNode) {
    final String? source = _attributes.read(navigationContentNode, 'src');
    if (source == null || source.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation content: content source is missing.');
    }
    return EpubNavigationContent(
      id: _attributes.read(navigationContentNode, 'id'),
      source: source,
    );
  }

  /// An `<li>` carrying a `<span>` rather than an `<a>` has no href at all,
  /// which is legal in a nav document - so, unlike EPUB2, a null source here
  /// is not a parsing error.
  EpubNavigationContent readNavigationContentV3(
      xml.XmlElement navigationContentNode, String navBase) {
    final String? href = _attributes.read(navigationContentNode, 'href');
    return EpubNavigationContent(
      id: _attributes.read(navigationContentNode, 'id'),
      source: href == null || navBase.isEmpty || href.startsWith(navBase)
          ? href
          : path.normalize(navBase + href),
    );
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
    return EpubNavigationDocAuthor(authors: _textsOf(docAuthorNode));
  }

  EpubNavigationDocTitle readNavigationDocTitle(xml.XmlElement docTitleNode) {
    return EpubNavigationDocTitle(titles: _textsOf(docTitleNode));
  }

  /// The text of every `<text>` child of [node].
  List<String> _textsOf(xml.XmlElement node) => _childrenNamed(node, 'text')
      .map((xml.XmlElement textNode) => textNode.innerText)
      .toUnmodifiableList();

  EpubNavigationHead readNavigationHead(xml.XmlElement headNode) {
    return EpubNavigationHead(
        metadata: _childrenNamed(headNode, 'meta')
            .map(_readNavigationHeadMeta)
            .toUnmodifiableList());
  }

  EpubNavigationHeadMeta _readNavigationHeadMeta(xml.XmlElement metaNode) {
    final String? name = _attributes.read(metaNode, 'name');
    if (name == null || name.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation meta: meta name is missing.');
    }
    final String? content = _attributes.read(metaNode, 'content');
    if (content == null) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation meta: meta content is missing.');
    }
    return EpubNavigationHeadMeta(
      name: name,
      content: content,
      scheme: _attributes.read(metaNode, 'scheme'),
    );
  }

  EpubNavigationLabel readNavigationLabel(xml.XmlElement navigationLabelNode) {
    final xml.XmlElement? navigationLabelTextNode = navigationLabelNode
        .findElements('text', namespace: navigationLabelNode.name.namespaceUri)
        .firstOrNull;
    if (navigationLabelTextNode == null) {
      throw const EpubMissingElementException(
          'Incorrect EPUB navigation label: label text element is missing.');
    }

    return EpubNavigationLabel(text: navigationLabelTextNode.innerText);
  }

  EpubNavigationLabel readNavigationLabelV3(
      xml.XmlElement navigationLabelNode) {
    return EpubNavigationLabel(text: navigationLabelNode.innerText.trim());
  }

  /// NCX requires a `<navList>` to carry at least one `<navLabel>` and one
  /// `<navTarget>`; one that lacks either reads with that list empty rather
  /// than refusing the book, since nothing downstream reads nav lists.
  EpubNavigationList readNavigationList(xml.XmlElement navigationListNode) {
    return EpubNavigationList(
      id: _attributes.read(navigationListNode, 'id'),
      className: _attributes.read(navigationListNode, 'class'),
      navigationLabels: _childrenNamed(navigationListNode, 'navlabel')
          .map(readNavigationLabel)
          .toUnmodifiableList(),
      navigationTargets: _childrenNamed(navigationListNode, 'navtarget')
          .map(readNavigationTarget)
          .toUnmodifiableList(),
    );
  }

  EpubNavigationMap readNavigationMap(xml.XmlElement navigationMapNode) {
    return EpubNavigationMap(
        points: _childrenNamed(navigationMapNode, 'navpoint')
            .map(readNavigationPoint)
            .toUnmodifiableList());
  }

  EpubNavigationMap readNavigationMapV3(
      xml.XmlElement navigationMapNode, String navBase) {
    return EpubNavigationMap(
        points: _childrenNamed(navigationMapNode, 'li')
            .map((xml.XmlElement navigationPointNode) =>
                readNavigationPointV3(navigationPointNode, navBase))
            .toUnmodifiableList());
  }

  EpubNavigationPageList readNavigationPageList(
      xml.XmlElement navigationPageListNode) {
    return EpubNavigationPageList(
        targets: navigationPageListNode.children
            .whereType<xml.XmlElement>()
            .where((xml.XmlElement pageTargetNode) =>
                pageTargetNode.name.local == 'pageTarget')
            .map(readNavigationPageTarget)
            .toUnmodifiableList());
  }

  EpubNavigationPageTarget readNavigationPageTarget(
      xml.XmlElement navigationPageTargetNode) {
    final EpubNavigationPageTargetType? type =
        _pageTargetTypeOf(navigationPageTargetNode);
    if (type == EpubNavigationPageTargetType.undefined) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation page target: page target type is missing.');
    }

    final _NavigationTargetChildren children =
        _readTargetChildren(navigationPageTargetNode);
    if (children.navigationLabels.isEmpty) {
      throw const EpubMissingElementException(
          'Incorrect EPUB navigation page target: at least one navLabel element is required.');
    }

    return EpubNavigationPageTarget(
      id: _attributes.read(navigationPageTargetNode, 'id') ?? '',
      value: _attributes.read(navigationPageTargetNode, 'value'),
      type: type ?? EpubNavigationPageTargetType.undefined,
      className: _attributes.read(navigationPageTargetNode, 'class'),
      playOrder: _attributes.read(navigationPageTargetNode, 'playorder') ?? '',
      navigationLabels: children.navigationLabels,
      content: children.content,
    );
  }

  /// The page target's `type`, or null when it is absent or names no page
  /// type this parser knows. `undefined` is not an NCX page type; a book that
  /// writes it is refused by the caller.
  EpubNavigationPageTargetType? _pageTargetTypeOf(
      xml.XmlElement navigationPageTargetNode) {
    final String? typeValue =
        _attributes.read(navigationPageTargetNode, 'type');
    if (typeValue == null) {
      return null;
    }
    return EnumFromString<EpubNavigationPageTargetType>(
            EpubNavigationPageTargetType.values)
        .get(typeValue);
  }

  /// The labels and content of a page or nav target, read in document order
  /// so a malformed child fails where it stands. The last `<content>` is the
  /// target's; with none, the content has no source.
  _NavigationTargetChildren _readTargetChildren(xml.XmlElement targetNode) {
    final List<EpubNavigationLabel> navigationLabels = <EpubNavigationLabel>[];
    EpubNavigationContent content = const EpubNavigationContent();
    for (final xml.XmlElement targetChildNode
        in targetNode.children.whereType<xml.XmlElement>()) {
      switch (targetChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          navigationLabels.add(readNavigationLabel(targetChildNode));
        case 'content':
          content = readNavigationContent(targetChildNode);
      }
    }
    return _NavigationTargetChildren(
        navigationLabels: navigationLabels.toUnmodifiableList(),
        content: content);
  }

  EpubNavigationPoint readNavigationPoint(xml.XmlElement navigationPointNode) {
    final String? id = _attributes.read(navigationPointNode, 'id');
    if (id == null || id.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation point: point ID is missing.');
    }

    final List<EpubNavigationLabel> navigationLabels = <EpubNavigationLabel>[];
    EpubNavigationContent? content;
    final List<EpubNavigationPoint> childNavigationPoints =
        <EpubNavigationPoint>[];
    for (final xml.XmlElement navigationPointChildNode
        in navigationPointNode.children.whereType<xml.XmlElement>()) {
      switch (navigationPointChildNode.name.local.toLowerCase()) {
        case 'navlabel':
          navigationLabels.add(readNavigationLabel(navigationPointChildNode));
        case 'content':
          content = readNavigationContent(navigationPointChildNode);
        case 'navpoint':
          childNavigationPoints
              .add(readNavigationPoint(navigationPointChildNode));
      }
    }

    return EpubNavigationPoint(
      id: id,
      className: _attributes.read(navigationPointNode, 'class'),
      playOrder: _attributes.read(navigationPointNode, 'playorder') ?? '',
      navigationLabels: _requireNavigationLabels(navigationLabels, id),
      content: _requireNavigationContent(content, id),
      childNavigationPoints: childNavigationPoints.toUnmodifiableList(),
    );
  }

  /// A navigation point with no label has nothing to show; EPUB2 and EPUB3
  /// refuse it alike.
  List<EpubNavigationLabel> _requireNavigationLabels(
      List<EpubNavigationLabel> navigationLabels, String id) {
    if (navigationLabels.isEmpty) {
      throw EpubMissingElementException(
          'EPUB parsing error: navigation point $id should contain at least one navigation label.');
    }
    return navigationLabels.toUnmodifiableList();
  }

  /// A navigation point with no content has nowhere to go; EPUB2 and EPUB3
  /// refuse it alike.
  EpubNavigationContent _requireNavigationContent(
      EpubNavigationContent? content, String id) {
    if (content == null) {
      throw EpubMissingElementException(
          'EPUB parsing error: navigation point $id should contain content.');
    }
    return content;
  }

  /// An EPUB3 nav entry: its `<a>` or `<span>` is both the label and the
  /// content, and a nested `<ol>` holds its children. A nav document entry
  /// has no NCX id or play order, so both read as empty.
  EpubNavigationPoint readNavigationPointV3(
      xml.XmlElement navigationPointNode, String navBase) {
    final List<EpubNavigationLabel> navigationLabels = <EpubNavigationLabel>[];
    EpubNavigationContent? content;
    final List<EpubNavigationPoint> childNavigationPoints =
        <EpubNavigationPoint>[];
    for (final xml.XmlElement navigationPointChildNode
        in navigationPointNode.children.whereType<xml.XmlElement>()) {
      switch (navigationPointChildNode.name.local.toLowerCase()) {
        case 'a':
        case 'span':
          navigationLabels.add(readNavigationLabelV3(navigationPointChildNode));
          content = readNavigationContentV3(navigationPointChildNode, navBase);
        case 'ol':
          childNavigationPoints.addAll(
              readNavigationMapV3(navigationPointChildNode, navBase).points);
      }
    }

    return EpubNavigationPoint(
      id: '',
      playOrder: '',
      navigationLabels: _requireNavigationLabels(navigationLabels, ''),
      content: _requireNavigationContent(content, ''),
      childNavigationPoints: childNavigationPoints.toUnmodifiableList(),
    );
  }

  EpubNavigationTarget readNavigationTarget(
      xml.XmlElement navigationTargetNode) {
    final String? id = _attributes.read(navigationTargetNode, 'id');
    if (id == null || id.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB navigation target: navigation target ID is missing.');
    }

    final _NavigationTargetChildren children =
        _readTargetChildren(navigationTargetNode);
    if (children.navigationLabels.isEmpty) {
      throw const EpubMissingElementException(
          'Incorrect EPUB navigation target: at least one navLabel element is required.');
    }

    return EpubNavigationTarget(
      id: id,
      className: _attributes.read(navigationTargetNode, 'class'),
      value: _attributes.read(navigationTargetNode, 'value'),
      playOrder: _attributes.read(navigationTargetNode, 'playorder') ?? '',
      navigationLabels: children.navigationLabels,
      content: children.content,
    );
  }
}

/// What a page target and a nav target share: their labels and the content
/// they point at.
class _NavigationTargetChildren {
  const _NavigationTargetChildren(
      {required this.navigationLabels, required this.content});

  final List<EpubNavigationLabel> navigationLabels;
  final EpubNavigationContent content;
}
