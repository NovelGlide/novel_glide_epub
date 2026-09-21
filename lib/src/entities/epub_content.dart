import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_byte_content_file.dart';
import 'epub_content_file.dart';
import 'epub_text_content_file.dart';

class EpubContent {

  EpubContent() {
    Html = <String, EpubTextContentFile>{};
    Css = <String, EpubTextContentFile>{};
    Images = <String, EpubByteContentFile>{};
    Fonts = <String, EpubByteContentFile>{};
    AllFiles = <String, EpubContentFile>{};
  }
  Map<String, EpubTextContentFile>? Html;
  Map<String, EpubTextContentFile>? Css;
  Map<String, EpubByteContentFile>? Images;
  Map<String, EpubByteContentFile>? Fonts;
  Map<String, EpubContentFile>? AllFiles;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      ...Html!.keys.map((String key) => key.hashCode),
      ...Html!.values.map((EpubTextContentFile value) => value.hashCode),
      ...Css!.keys.map((String key) => key.hashCode),
      ...Css!.values.map((EpubTextContentFile value) => value.hashCode),
      ...Images!.keys.map((String key) => key.hashCode),
      ...Images!.values.map((EpubByteContentFile value) => value.hashCode),
      ...Fonts!.keys.map((String key) => key.hashCode),
      ...Fonts!.values.map((EpubByteContentFile value) => value.hashCode),
      ...AllFiles!.keys.map((String key) => key.hashCode),
      ...AllFiles!.values.map((EpubContentFile value) => value.hashCode),
    ];

    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubContent) {
      return false;
    }
    return collections.mapsEqual(Html, other.Html) &&
        collections.mapsEqual(Css, other.Css) &&
        collections.mapsEqual(Images, other.Images) &&
        collections.mapsEqual(Fonts, other.Fonts) &&
        collections.mapsEqual(AllFiles, other.AllFiles);
  }
}
