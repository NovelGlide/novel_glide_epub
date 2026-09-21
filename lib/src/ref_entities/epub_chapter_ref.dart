import 'dart:async';

import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_text_content_file_ref.dart';

class EpubChapterRef {
  // Referece to Text content reader.
  EpubTextContentFileRef? epubTextContentFileRef;
  // If the chapter is split into multiple files, this list contains the references to content readers of the other files.
  List<EpubTextContentFileRef> otherTextContentFileRefs = [];

  String? Title;
  String? ContentFileName;
  String? Anchor;
  List<EpubChapterRef>? SubChapters;
  // If the chapter is split into multiple files, this list contains the names of the other files.
  List<String> OtherContentFileNames = [];

  EpubChapterRef(this.epubTextContentFileRef);

  @override
  int get hashCode {
    var objects = [
      Title.hashCode,
      ContentFileName.hashCode,
      // The two split-chapter lists are hashed by ELEMENT, like
      // `SubChapters`: every ref gets its own list instance from the field
      // initialiser, so hashing the list object would give two refs over one
      // chapter two different hash codes.
      ...OtherContentFileNames.map((fileName) => fileName.hashCode),
      ...otherTextContentFileRefs.map((fileRef) => fileRef.hashCode),
      Anchor.hashCode,
      epubTextContentFileRef.hashCode,
      ...SubChapters?.map((subChapter) => subChapter.hashCode) ?? [0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubChapterRef &&
      Title == other.Title &&
      ContentFileName == other.ContentFileName &&
      collections.listsEqual(
          OtherContentFileNames, other.OtherContentFileNames) &&
      Anchor == other.Anchor &&
      epubTextContentFileRef == other.epubTextContentFileRef &&
      collections.listsEqual(
          otherTextContentFileRefs, other.otherTextContentFileRefs) &&
      collections.listsEqual(SubChapters, other.SubChapters);

  Future<String> readHtmlContent() async {
    // Started before the other parts so all of them read concurrently.
    var contentFuture = epubTextContentFileRef!.readContentAsText();
    if (OtherContentFileNames.isEmpty) {
      return contentFuture;
    }

    var contents = await Future.wait(<Future<String>>[
      contentFuture,
      for (var otherContentFileRef in otherTextContentFileRefs)
        otherContentFileRef.readContentAsText(),
    ]);
    return contents.join();
  }

  @override
  String toString() {
    return 'Title: $Title, Subchapter count: ${SubChapters!.length}';
  }
}
