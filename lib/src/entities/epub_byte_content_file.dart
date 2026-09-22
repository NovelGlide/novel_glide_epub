import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_content_file.dart';

class EpubByteContentFile extends EpubContentFile {
  List<int>? content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      contentMimeType.hashCode,
      contentType.hashCode,
      fileName.hashCode,
      ...content?.map((int content) => content.hashCode) ?? <int>[0],
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubByteContentFile) {
      return false;
    }
    return collections.listsEqual(content, other.content) &&
        contentMimeType == other.contentMimeType &&
        contentType == other.contentType &&
        fileName == other.fileName;
  }
}
