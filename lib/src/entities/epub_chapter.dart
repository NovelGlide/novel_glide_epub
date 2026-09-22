import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

class EpubChapter {
  String? title;
  String? contentFileName;
  String? anchor;
  String? htmlContent;
  List<EpubChapter>? subChapters;
  List<String> otherContentFileNames = <String>[];

  @override
  int get hashCode {
    final List<int> objects = <int>[
      title.hashCode,
      contentFileName.hashCode,
      // By ELEMENT, like every other collection field here: the list is
      // handed to each instance fresh, so hashing the list object would give
      // two chapters with identical data two different hash codes.
      ...otherContentFileNames.map((String fileName) => fileName.hashCode),
      anchor.hashCode,
      htmlContent.hashCode,
      ...subChapters?.map((EpubChapter subChapter) => subChapter.hashCode) ??
          <int>[0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubChapter &&
      title == other.title &&
      contentFileName == other.contentFileName &&
      collections.listsEqual(
          otherContentFileNames, other.otherContentFileNames) &&
      anchor == other.anchor &&
      htmlContent == other.htmlContent &&
      collections.listsEqual(subChapters, other.subChapters);

  @override
  String toString() {
    return 'Title: $title, Subchapter count: ${subChapters!.length}';
  }
}
