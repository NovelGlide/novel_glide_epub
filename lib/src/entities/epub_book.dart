import 'package:image/image.dart';
import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_chapter.dart';
import 'epub_content.dart';
import 'epub_schema.dart';

class EpubBook {
  String? Title;
  String? Author;
  List<String?>? AuthorList;
  EpubSchema? Schema;
  EpubContent? Content;
  Image? CoverImage;
  List<EpubChapter>? Chapters;

  @override
  int get hashCode {
    var objects = [
      Title.hashCode,
      Author.hashCode,
      Schema.hashCode,
      Content.hashCode,
      ...CoverImage?.getBytes().map((byte) => byte.hashCode) ?? [0],
      ...AuthorList?.map((author) => author.hashCode) ?? [0],
      ...Chapters?.map((chapter) => chapter.hashCode) ?? [0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubBook &&
      Title == other.Title &&
      Author == other.Author &&
      collections.listsEqual(AuthorList, other.AuthorList) &&
      Schema == other.Schema &&
      Content == other.Content &&
      _coversEqual(CoverImage, other.CoverImage) &&
      collections.listsEqual(Chapters, other.Chapters);

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
