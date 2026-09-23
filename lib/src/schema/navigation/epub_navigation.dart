import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_doc_author.dart';
import 'epub_navigation_doc_title.dart';
import 'epub_navigation_head.dart';
import 'epub_navigation_list.dart';
import 'epub_navigation_map.dart';
import 'epub_navigation_page_list.dart';

/// A book's table of contents, in the shape of an EPUB 2 NCX.
///
/// An EPUB 3 nav document is read into the same shape. It has no NCX head,
/// doc author or nav list, so those read as empty, and its doc title is the
/// package's `dc:title`s.
class EpubNavigation {
  const EpubNavigation({
    required this.head,
    required this.docTitle,
    required this.navMap,
    this.docAuthors = const <EpubNavigationDocAuthor>[],
    this.pageList,
    this.navLists = const <EpubNavigationList>[],
  });

  final EpubNavigationHead head;
  final EpubNavigationDocTitle docTitle;
  final List<EpubNavigationDocAuthor> docAuthors;
  final EpubNavigationMap navMap;

  /// Null when the NCX has no `<pageList>`, which it makes optional. An
  /// EPUB 3 nav document's page list is not read, so it is null there too.
  final EpubNavigationPageList? pageList;
  final List<EpubNavigationList> navLists;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      head.hashCode,
      docTitle.hashCode,
      navMap.hashCode,
      pageList.hashCode,
      ...docAuthors.map((EpubNavigationDocAuthor author) => author.hashCode),
      ...navLists.map((EpubNavigationList navList) => navList.hashCode)
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigation) {
      return false;
    }

    if (!collections.listsEqual(docAuthors, other.docAuthors)) {
      return false;
    }
    if (!collections.listsEqual(navLists, other.navLists)) {
      return false;
    }

    return head == other.head &&
        docTitle == other.docTitle &&
        navMap == other.navMap &&
        pageList == other.pageList;
  }
}
