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
  EpubBookRef(Archive epubArchive) {
    _epubArchive = epubArchive;
  }
  Archive? _epubArchive;

  String? Title;
  String? Author;
  List<String?>? AuthorList;
  EpubSchema? Schema;
  EpubContentRef? Content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      Title.hashCode,
      Author.hashCode,
      Schema.hashCode,
      Content.hashCode,
      ...AuthorList?.map((String? author) => author.hashCode) ?? <int>[0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubBookRef) {
      return false;
    }

    return Title == other.Title &&
        Author == other.Author &&
        Schema == other.Schema &&
        Content == other.Content &&
        collections.listsEqual(AuthorList, other.AuthorList);
  }

  Archive? EpubArchive() {
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
