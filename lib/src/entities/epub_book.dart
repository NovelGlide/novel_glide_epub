import 'package:image/image.dart';
import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_chapter.dart';
import 'epub_content.dart';
import 'epub_schema.dart';

class EpubBook {
  String? title;
  String? author;
  List<String?>? authorList;
  EpubSchema? schema;
  EpubContent? content;
  Image? coverImage;
  List<EpubChapter>? chapters;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      title.hashCode,
      author.hashCode,
      schema.hashCode,
      content.hashCode,
      ...coverImage?.getBytes().map((int byte) => byte.hashCode) ?? <int>[0],
      ...authorList?.map((String? author) => author.hashCode) ?? <int>[0],
      ...chapters?.map((EpubChapter chapter) => chapter.hashCode) ?? <int>[0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubBook &&
      title == other.title &&
      author == other.author &&
      collections.listsEqual(authorList, other.authorList) &&
      schema == other.schema &&
      content == other.content &&
      _coversEqual(coverImage, other.coverImage) &&
      collections.listsEqual(chapters, other.chapters);

  /// Two covers match when neither book has one, or when both decode to the
  /// same bytes. A cover on one side only is a DIFFERENCE, not an error — the
  /// comparison answers false instead of dereferencing the absent side.
  static bool _coversEqual(Image? cover, Image? other) {
    if (cover == null || other == null) {
      return cover == null && other == null;
    }
    return collections.listsEqual(cover.getBytes(), other.getBytes());
  }
}
