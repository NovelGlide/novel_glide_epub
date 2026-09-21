import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

class EpubChapter {
  String? Title;
  String? ContentFileName;
  String? Anchor;
  String? HtmlContent;
  List<EpubChapter>? SubChapters;
  List<String> OtherContentFileNames = <String>[];

  @override
  int get hashCode {
    final List<int> objects = <int>[
      Title.hashCode,
      ContentFileName.hashCode,
      // By ELEMENT, like every other collection field here: the list is
      // handed to each instance fresh, so hashing the list object would give
      // two chapters with identical data two different hash codes.
      ...OtherContentFileNames.map((String fileName) => fileName.hashCode),
      Anchor.hashCode,
      HtmlContent.hashCode,
      ...SubChapters?.map((EpubChapter subChapter) => subChapter.hashCode) ?? <int>[0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubChapter &&
      Title == other.Title &&
      ContentFileName == other.ContentFileName &&
      collections.listsEqual(
          OtherContentFileNames, other.OtherContentFileNames) &&
      Anchor == other.Anchor &&
      HtmlContent == other.HtmlContent &&
      collections.listsEqual(SubChapters, other.SubChapters);

  @override
  String toString() {
    return 'Title: $Title, Subchapter count: ${SubChapters!.length}';
  }
}
