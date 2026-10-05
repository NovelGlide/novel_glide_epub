import 'package:equatable/equatable.dart';
import 'package:image/image.dart';

import 'epub_chapter.dart';
import 'epub_content.dart';
import 'epub_schema.dart';

class EpubBook extends Equatable {
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
  List<Object?> get props =>
      <Object?>[title, authorList, schema, content, _coverBytes, chapters];

  /// The cover is compared by the bytes it decodes to, not as an image: two
  /// reads of one book decode two images, equal pixel for pixel. Null when
  /// the book has no cover.
  List<int>? get _coverBytes => coverImage?.getBytes();

  /// The title and the number of chapters; never the content or the cover.
  @override
  String toString() {
    return 'Title: $title, Chapter count: ${chapters.length}';
  }
}
