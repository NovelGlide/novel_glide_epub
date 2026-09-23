import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart';
import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import '../entities/epub_schema.dart';
import '../readers/book_cover_reader.dart';
import '../readers/chapter_reader.dart';
import 'epub_chapter_ref.dart';
import 'epub_content_ref.dart';

class EpubBookRef {
  const EpubBookRef({
    required Archive epubArchive,
    required this.title,
    required this.authorList,
    required this.schema,
    required this.content,
  }) : _epubArchive = epubArchive;

  final Archive _epubArchive;

  /// The first `dc:title`; empty when the package has none, although OPF
  /// requires one.
  final String title;

  /// Every `dc:creator`'s text, in document order; empty when the package
  /// names no creator. How the names are joined for display is the caller's
  /// decision.
  final List<String> authorList;
  final EpubSchema schema;
  final EpubContentRef content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      title.hashCode,
      schema.hashCode,
      content.hashCode,
      ...authorList.map((String author) => author.hashCode),
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubBookRef) {
      return false;
    }

    return title == other.title &&
        schema == other.schema &&
        content == other.content &&
        collections.listsEqual(authorList, other.authorList);
  }

  Archive epubArchive() {
    return _epubArchive;
  }

  Future<List<EpubChapterRef>> getChapters() async {
    return const ChapterReader().getChapters(this);
  }

  Future<Image?> readCover() async {
    return await const BookCoverReader().readBookCover(this);
  }

  Future<Uint8List?> readCoverBytes() async {
    return await const BookCoverReader().readBookCoverBytes(this);
  }
}
