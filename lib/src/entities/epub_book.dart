import 'package:image/image.dart';
import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_chapter.dart';
import 'epub_content.dart';
import 'epub_schema.dart';

class EpubBook {
  const EpubBook({
    required this.title,
    required this.authorList,
    required this.schema,
    required this.content,
    required this.chapters,
    this.coverImage,
  });

  /// The first `dc:title`; empty when the package has none, although OPF
  /// requires one.
  final String title;

  /// Every `dc:creator`'s text, in document order; empty when the package
  /// names no creator. How the names are joined for display is the caller's
  /// decision.
  final List<String> authorList;
  final EpubSchema schema;
  final EpubContent content;

  /// The cover an EPUB 2 `<meta name="cover">` names, decoded. Null when the
  /// book has no such meta, or `package:image` finds no image in its bytes.
  /// An EPUB 3 `cover-image` manifest item is not read here, so an EPUB 3
  /// book's cover is null; `EpubBookRef.readCoverBytes` reads both.
  final Image? coverImage;
  final List<EpubChapter> chapters;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      title.hashCode,
      schema.hashCode,
      content.hashCode,
      ...coverImage?.getBytes().map((int byte) => byte.hashCode) ?? <int>[0],
      ...authorList.map((String author) => author.hashCode),
      ...chapters.map((EpubChapter chapter) => chapter.hashCode),
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubBook &&
      title == other.title &&
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
