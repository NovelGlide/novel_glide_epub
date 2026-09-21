import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_navigation_doc_author.dart';
import 'epub_navigation_doc_title.dart';
import 'epub_navigation_head.dart';
import 'epub_navigation_list.dart';
import 'epub_navigation_map.dart';
import 'epub_navigation_page_list.dart';

class EpubNavigation {
  EpubNavigationHead? Head;
  EpubNavigationDocTitle? DocTitle;
  List<EpubNavigationDocAuthor>? DocAuthors;
  EpubNavigationMap? NavMap;
  EpubNavigationPageList? PageList;
  List<EpubNavigationList>? NavLists;

  @override
  int get hashCode {
    var objects = [
      Head.hashCode,
      DocTitle.hashCode,
      NavMap.hashCode,
      PageList.hashCode,
      ...DocAuthors?.map((author) => author.hashCode) ?? [0],
      ...NavLists?.map((navList) => navList.hashCode) ?? [0]
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigation) {
      return false;
    }

    if (!collections.listsEqual(DocAuthors, other.DocAuthors)) {
      return false;
    }
    if (!collections.listsEqual(NavLists, other.NavLists)) {
      return false;
    }

    return Head == other.Head &&
        DocTitle == other.DocTitle &&
        NavMap == other.NavMap &&
        PageList == other.PageList;
  }
}
