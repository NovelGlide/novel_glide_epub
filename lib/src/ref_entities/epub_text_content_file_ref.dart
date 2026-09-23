import 'dart:async';

import 'epub_content_file_ref.dart';

class EpubTextContentFileRef extends EpubContentFileRef {
  const EpubTextContentFileRef({
    required super.epubArchive,
    required super.contentDirectoryPath,
    required super.fileName,
    required super.contentType,
    required super.contentMimeType,
  });

  Future<String> readContentAsync() async {
    return readContentAsText();
  }
}
