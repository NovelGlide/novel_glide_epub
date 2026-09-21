import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_content_file.dart';

class EpubByteContentFile extends EpubContentFile {
  List<int>? Content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      ContentMimeType.hashCode,
      ContentType.hashCode,
      FileName.hashCode,
      ...Content?.map((int content) => content.hashCode) ?? <int>[0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubByteContentFile) {
      return false;
    }
    return collections.listsEqual(Content, other.Content) &&
        ContentMimeType == other.ContentMimeType &&
        ContentType == other.ContentType &&
        FileName == other.FileName;
  }
}
