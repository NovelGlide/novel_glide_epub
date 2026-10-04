import 'dart:async';

import 'package:equatable/equatable.dart';

import 'epub_text_content_file_ref.dart';

class EpubChapterRef extends Equatable {
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
  List<Object?> get props => <Object?>[
        epubTextContentFileRef,
        otherTextContentFileRefs,
        title,
        contentFileName,
        anchor,
        subChapters,
        otherContentFileNames
      ];

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
