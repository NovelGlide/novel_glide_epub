import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_byte_content_file.dart';
import 'epub_content_file.dart';
import 'epub_text_content_file.dart';

/// Every manifest file, read into memory.
///
/// Each map is keyed by the file's decoded name, the same string as the
/// file's [EpubContentFile.fileName], so a link finds its file whether the
/// book escapes the name or writes it raw. Look a link up by its decoded
/// form (`%E7%AC%AC.xhtml` and `第.xhtml` are one key, `第.xhtml`).
class EpubContent {
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
  int get hashCode {
    final List<int> objects = <int>[
      ...html.keys.map((String key) => key.hashCode),
      ...html.values.map((EpubTextContentFile value) => value.hashCode),
      ...css.keys.map((String key) => key.hashCode),
      ...css.values.map((EpubTextContentFile value) => value.hashCode),
      ...images.keys.map((String key) => key.hashCode),
      ...images.values.map((EpubByteContentFile value) => value.hashCode),
      ...fonts.keys.map((String key) => key.hashCode),
      ...fonts.values.map((EpubByteContentFile value) => value.hashCode),
      ...allFiles.keys.map((String key) => key.hashCode),
      ...allFiles.values.map((EpubContentFile value) => value.hashCode),
    ];

    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubContent) {
      return false;
    }
    return collections.mapsEqual(html, other.html) &&
        collections.mapsEqual(css, other.css) &&
        collections.mapsEqual(images, other.images) &&
        collections.mapsEqual(fonts, other.fonts) &&
        collections.mapsEqual(allFiles, other.allFiles);
  }
}
