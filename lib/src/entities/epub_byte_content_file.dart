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
}
