import 'package:equatable/equatable.dart';

import 'epub_byte_content_file.dart';
import 'epub_content_file.dart';
import 'epub_text_content_file.dart';

/// Every manifest file, read into memory.
///
/// Each map is keyed by the file's decoded name, the same string as the
/// file's [EpubContentFile.fileName], so a link finds its file whether the
/// book escapes the name or writes it raw. Look a link up by its decoded
/// form (`%E7%AC%AC.xhtml` and `第.xhtml` are one key, `第.xhtml`).
class EpubContent extends Equatable {
  const EpubContent({
    this.html = const <String, EpubTextContentFile>{},
    this.css = const <String, EpubTextContentFile>{},
    this.images = const <String, EpubByteContentFile>{},
    this.fonts = const <String, EpubByteContentFile>{},
    this.allFiles = const <String, EpubContentFile>{},
  });

  final Map<String, EpubTextContentFile> html;
  final Map<String, EpubTextContentFile> css;
  final Map<String, EpubByteContentFile> images;
  final Map<String, EpubByteContentFile> fonts;

  /// Every file, including those in the four named maps.
  final Map<String, EpubContentFile> allFiles;

  @override
  List<Object?> get props => <Object?>[html, css, images, fonts, allFiles];

  /// How many files each map holds; never a file's content.
  @override
  String toString() {
    return 'HTML: ${html.length}, CSS: ${css.length}, '
        'Images: ${images.length}, Fonts: ${fonts.length}, '
        'All files: ${allFiles.length}';
  }
}
