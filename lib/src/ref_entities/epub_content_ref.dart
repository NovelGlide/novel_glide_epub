import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_byte_content_file_ref.dart';
import 'epub_content_file_ref.dart';
import 'epub_text_content_file_ref.dart';

/// Every manifest file, as a reference read on demand.
///
/// Each map is keyed by the file's decoded name, the same string as the
/// file's [EpubContentFileRef.fileName], so a link finds its file whether
/// the book escapes the name or writes it raw. Look a link up by its decoded
/// form (`%E7%AC%AC.xhtml` and `第.xhtml` are one key, `第.xhtml`).
class EpubContentRef {
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
  int get hashCode {
    final List<int> objects = <int>[
      ...html.keys.map((String key) => key.hashCode),
      ...html.values.map((EpubTextContentFileRef value) => value.hashCode),
      ...css.keys.map((String key) => key.hashCode),
      ...css.values.map((EpubTextContentFileRef value) => value.hashCode),
      ...images.keys.map((String key) => key.hashCode),
      ...images.values.map((EpubByteContentFileRef value) => value.hashCode),
      ...fonts.keys.map((String key) => key.hashCode),
      ...fonts.values.map((EpubByteContentFileRef value) => value.hashCode),
      ...allFiles.keys.map((String key) => key.hashCode),
      ...allFiles.values.map((EpubContentFileRef value) => value.hashCode)
    ];

    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubContentRef) {
      return false;
    }

    return collections.mapsEqual(html, other.html) &&
        collections.mapsEqual(css, other.css) &&
        collections.mapsEqual(images, other.images) &&
        collections.mapsEqual(fonts, other.fonts) &&
        collections.mapsEqual(allFiles, other.allFiles);
  }
}
