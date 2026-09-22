import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_doc_author.dart';
import 'epub_navigation_doc_title.dart';
import 'epub_navigation_head.dart';
import 'epub_navigation_list.dart';
import 'epub_navigation_map.dart';
import 'epub_navigation_page_list.dart';

class EpubNavigation {
  EpubNavigationHead? head;
  EpubNavigationDocTitle? docTitle;
  List<EpubNavigationDocAuthor>? docAuthors;
  EpubNavigationMap? navMap;
  EpubNavigationPageList? pageList;
  List<EpubNavigationList>? navLists;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      head.hashCode,
      docTitle.hashCode,
      navMap.hashCode,
      pageList.hashCode,
      ...docAuthors?.map((EpubNavigationDocAuthor author) => author.hashCode) ??
          <int>[0],
      ...navLists?.map((EpubNavigationList navList) => navList.hashCode) ??
          <int>[0]
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
