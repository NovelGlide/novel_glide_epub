import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

class EpubChapter {
  const EpubChapter({
    required this.title,
    required this.contentFileName,
    required this.htmlContent,
    this.anchor,
    this.subChapters = const <EpubChapter>[],
    this.otherContentFileNames = const <String>[],
  });

  final String title;

  /// The decoded file name, a key of `EpubContent.html`.
  final String contentFileName;

  /// The fragment after `#` in the navigation's link; null when it has none.
  final String? anchor;
  final String htmlContent;
  final List<EpubChapter> subChapters;
  final List<String> otherContentFileNames;

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
      ...subChapters.map((EpubChapter subChapter) => subChapter.hashCode),
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
    return 'Title: $title, Subchapter count: ${subChapters.length}';
  }
}
