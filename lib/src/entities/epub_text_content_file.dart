import 'epub_content_file.dart';

class EpubTextContentFile extends EpubContentFile {
  const EpubTextContentFile({
    required super.fileName,
    required super.contentType,
    required super.contentMimeType,
    required this.content,
  });

  final String content;

  @override
  List<Object?> get props =>
      <Object?>[fileName, contentType, contentMimeType, content];
}
