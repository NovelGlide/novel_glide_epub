import 'dart:async';

import 'epub_content_file_ref.dart';

class EpubByteContentFileRef extends EpubContentFileRef {
  const EpubByteContentFileRef({
    required super.epubArchive,
    required super.contentDirectoryPath,
    required super.fileName,
    required super.contentType,
    required super.contentMimeType,
  });

  Future<List<int>> readContent() {
    return readContentAsBytes();
  }
}
