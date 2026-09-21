import 'dart:async';

import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_text_content_file_ref.dart';

class EpubChapterRef {

  EpubChapterRef(this.epubTextContentFileRef);
  // Referece to Text content reader.
  EpubTextContentFileRef? epubTextContentFileRef;
  // If the chapter is split into multiple files, this list contains the references to content readers of the other files.
  List<EpubTextContentFileRef> otherTextContentFileRefs = <EpubTextContentFileRef>[];

  String? Title;
  String? ContentFileName;
  String? Anchor;
  List<EpubChapterRef>? SubChapters;
  // If the chapter is split into multiple files, this list contains the names of the other files.
  List<String> OtherContentFileNames = <String>[];

  @override
  int get hashCode {
    final List<int> objects = <int>[
      Title.hashCode,
      ContentFileName.hashCode,
      // The two split-chapter lists are hashed by ELEMENT, like
      // `SubChapters`: every ref gets its own list instance from the field
      // initialiser, so hashing the list object would give two refs over one
      // chapter two different hash codes.
      ...OtherContentFileNames.map((String fileName) => fileName.hashCode),
      ...otherTextContentFileRefs.map((EpubTextContentFileRef fileRef) => fileRef.hashCode),
      Anchor.hashCode,
      epubTextContentFileRef.hashCode,
      ...SubChapters?.map((EpubChapterRef subChapter) => subChapter.hashCode) ?? <int>[0],
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
    final Future<String> contentFuture = epubTextContentFileRef!.readContentAsText();
    if (OtherContentFileNames.isEmpty) {
      return contentFuture;
    }

    final List<String> contents = await Future.wait(<Future<String>>[
      contentFuture,
      for (EpubTextContentFileRef otherContentFileRef in otherTextContentFileRefs)
        otherContentFileRef.readContentAsText(),
    ]);
    return contents.join();
  }

  @override
  String toString() {
    return 'Title: $Title, Subchapter count: ${SubChapters!.length}';
  }
}
