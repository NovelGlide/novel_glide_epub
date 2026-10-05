import 'package:equatable/equatable.dart';

import 'epub_content_type.dart';

/// One manifest file, read into memory: an `EpubTextContentFile` or an
/// `EpubByteContentFile`.
abstract class EpubContentFile extends Equatable {
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
  List<Object?> get props => <Object?>[fileName, contentType, contentMimeType];
}
