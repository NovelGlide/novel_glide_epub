import 'package:equatable/equatable.dart';

import 'epub_byte_content_file_ref.dart';
import 'epub_content_file_ref.dart';
import 'epub_text_content_file_ref.dart';

/// Every manifest file, as a reference read on demand.
///
/// Each map is keyed by the file's decoded name, the same string as the
/// file's [EpubContentFileRef.fileName], so a link finds its file whether
/// the book escapes the name or writes it raw. Look a link up by its decoded
/// form (`%E7%AC%AC.xhtml` and `第.xhtml` are one key, `第.xhtml`).
class EpubContentRef extends Equatable {
  const EpubContentRef({
    this.html = const <String, EpubTextContentFileRef>{},
    this.css = const <String, EpubTextContentFileRef>{},
    this.images = const <String, EpubByteContentFileRef>{},
    this.fonts = const <String, EpubByteContentFileRef>{},
    this.allFiles = const <String, EpubContentFileRef>{},
  });

  final Map<String, EpubTextContentFileRef> html;
  final Map<String, EpubTextContentFileRef> css;
  final Map<String, EpubByteContentFileRef> images;
  final Map<String, EpubByteContentFileRef> fonts;

  /// Every file, including those in the four named maps.
  final Map<String, EpubContentFileRef> allFiles;

  @override
  List<Object?> get props => <Object?>[html, css, images, fonts, allFiles];
}
