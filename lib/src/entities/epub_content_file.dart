import 'package:quiver/core.dart';

import 'epub_content_type.dart';

/// One manifest file, read into memory: an `EpubTextContentFile` or an
/// `EpubByteContentFile`.
abstract class EpubContentFile {
  const EpubContentFile({
    required this.fileName,
    required this.contentType,
    required this.contentMimeType,
  });

  /// The manifest href with its percent-escapes decoded, relative to the
  /// package document's directory.
  final String fileName;
  final EpubContentType contentType;
  final String contentMimeType;

  @override
  int get hashCode =>
      hash3(fileName.hashCode, contentType.hashCode, contentMimeType.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubContentFile) {
      return false;
    }
    return fileName == other.fileName &&
        contentType == other.contentType &&
        contentMimeType == other.contentMimeType;
  }
}
