import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_byte_content_file_ref.dart';
import 'epub_content_file_ref.dart';
import 'epub_text_content_file_ref.dart';

class EpubContentRef {

  EpubContentRef() {
    Html = <String, EpubTextContentFileRef>{};
    Css = <String, EpubTextContentFileRef>{};
    Images = <String, EpubByteContentFileRef>{};
    Fonts = <String, EpubByteContentFileRef>{};
    AllFiles = <String, EpubContentFileRef>{};
  }
  Map<String, EpubTextContentFileRef>? Html;
  Map<String, EpubTextContentFileRef>? Css;
  Map<String, EpubByteContentFileRef>? Images;
  Map<String, EpubByteContentFileRef>? Fonts;
  Map<String, EpubContentFileRef>? AllFiles;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      ...Html!.keys.map((String key) => key.hashCode),
      ...Html!.values.map((EpubTextContentFileRef value) => value.hashCode),
      ...Css!.keys.map((String key) => key.hashCode),
      ...Css!.values.map((EpubTextContentFileRef value) => value.hashCode),
      ...Images!.keys.map((String key) => key.hashCode),
      ...Images!.values.map((EpubByteContentFileRef value) => value.hashCode),
      ...Fonts!.keys.map((String key) => key.hashCode),
      ...Fonts!.values.map((EpubByteContentFileRef value) => value.hashCode),
      ...AllFiles!.keys.map((String key) => key.hashCode),
      ...AllFiles!.values.map((EpubContentFileRef value) => value.hashCode)
    ];

    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubContentRef) {
      return false;
    }

    return collections.mapsEqual(Html, other.Html) &&
        collections.mapsEqual(Css, other.Css) &&
        collections.mapsEqual(Images, other.Images) &&
        collections.mapsEqual(Fonts, other.Fonts) &&
        collections.mapsEqual(AllFiles, other.AllFiles);
  }
}
