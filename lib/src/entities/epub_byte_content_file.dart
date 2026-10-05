import 'epub_content_file.dart';

class EpubByteContentFile extends EpubContentFile {
  const EpubByteContentFile({
    required super.fileName,
    required super.contentType,
    required super.contentMimeType,
    required this.content,
  });

  final List<int> content;

  @override
  List<Object?> get props =>
      <Object?>[fileName, contentType, contentMimeType, content];

  /// The file's name, type and the length of its content; never the content.
  @override
  String toString() {
    return 'File name: $fileName, Content type: ${contentType.name}, '
        'MIME type: $contentMimeType, Length: ${content.length} bytes';
  }
}
