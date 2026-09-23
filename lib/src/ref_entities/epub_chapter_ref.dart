import 'dart:async';

import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_text_content_file_ref.dart';

class EpubChapterRef {
  const EpubChapterRef({
    required this.epubTextContentFileRef,
    required this.title,
    required this.contentFileName,
    this.anchor,
    this.subChapters = const <EpubChapterRef>[],
    this.otherTextContentFileRefs = const <EpubTextContentFileRef>[],
    this.otherContentFileNames = const <String>[],
  });

  final EpubTextContentFileRef epubTextContentFileRef;

  /// The rest of a chapter the producer split into several files, in
  /// the same order as [otherContentFileNames].
  final List<EpubTextContentFileRef> otherTextContentFileRefs;

  final String title;

  /// The decoded file name, a key of `EpubContentRef.html`.
  final String contentFileName;

  /// The fragment after `#` in the navigation's link; null when it has none.
  final String? anchor;
  final List<EpubChapterRef> subChapters;

  /// The file names of [otherTextContentFileRefs].
  final List<String> otherContentFileNames;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      title.hashCode,
      contentFileName.hashCode,
      // The two split-chapter lists are hashed by ELEMENT, like
      // `subChapters`: two refs over one chapter hold equal lists that are
      // not the same list, so hashing the list object would give them two
      // different hash codes.
      ...otherContentFileNames.map((String fileName) => fileName.hashCode),
      ...otherTextContentFileRefs
          .map((EpubTextContentFileRef fileRef) => fileRef.hashCode),
      anchor.hashCode,
      epubTextContentFileRef.hashCode,
      ...subChapters.map((EpubChapterRef subChapter) => subChapter.hashCode),
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) =>
      other is EpubChapterRef &&
      title == other.title &&
      contentFileName == other.contentFileName &&
      collections.listsEqual(
          otherContentFileNames, other.otherContentFileNames) &&
      anchor == other.anchor &&
      epubTextContentFileRef == other.epubTextContentFileRef &&
      collections.listsEqual(
          otherTextContentFileRefs, other.otherTextContentFileRefs) &&
      collections.listsEqual(subChapters, other.subChapters);

  /// The chapter's own file followed by its split parts, read concurrently
  /// and joined in that order.
  Future<String> readHtmlContent() async {
    final List<String> contents = await Future.wait(<Future<String>>[
      epubTextContentFileRef.readContentAsText(),
      for (EpubTextContentFileRef otherContentFileRef
          in otherTextContentFileRefs)
        otherContentFileRef.readContentAsText(),
    ]);
    return contents.join();
  }

  @override
  String toString() {
    return 'Title: $title, Subchapter count: ${subChapters.length}';
  }
}
