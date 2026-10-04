import 'package:equatable/equatable.dart';

class EpubChapter extends Equatable {
  const EpubChapter({
    required this.title,
    required this.contentFileName,
    required this.htmlContent,
    this.anchor,
    this.subChapters = const <EpubChapter>[],
    this.otherContentFileNames = const <String>[],
  });

  final String title;

  /// The decoded file name, a key of `EpubContent.html`.
  final String contentFileName;

  /// The fragment after `#` in the navigation's link; null when it has none.
  final String? anchor;
  final String htmlContent;
  final List<EpubChapter> subChapters;
  final List<String> otherContentFileNames;

  @override
  List<Object?> get props => <Object?>[
        title,
        contentFileName,
        anchor,
        htmlContent,
        subChapters,
        otherContentFileNames
      ];

  @override
  String toString() {
    return 'Title: $title, Subchapter count: ${subChapters.length}';
  }
}
