import 'dart:async';
import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:quiver/core.dart';

import '../entities/epub_content_type.dart';
import '../epub_exception.dart';
import '../utils/zip_path_resolver.dart';
import 'epub_book_ref.dart';

abstract class EpubContentFileRef {
  EpubContentFileRef(this.epubBookRef);
  late EpubBookRef epubBookRef;

  String? fileName;

  EpubContentType? contentType;
  String? contentMimeType;

  @override
  int get hashCode =>
      hash3(fileName.hashCode, contentMimeType.hashCode, contentType.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubContentFileRef) {
      return false;
    }

    return other.fileName == fileName &&
        other.contentMimeType == contentMimeType &&
        other.contentType == contentType;
  }

  ArchiveFile getContentFileEntry() {
    final String contentFilePath = const ZipPathResolver()
        .combine(epubBookRef.schema!.contentDirectoryPath, fileName);
    final ArchiveFile? contentFileEntry = epubBookRef
        .epubArchive()!
        .files
        .firstWhereOrNull((ArchiveFile x) => x.name == contentFilePath);
    if (contentFileEntry == null) {
      throw EpubMissingArchiveEntryException(
          'EPUB parsing error: file $contentFilePath not found in archive.');
    }
    return contentFileEntry;
  }

  List<int> getContentStream() {
    return openContentStream(getContentFileEntry());
  }

  List<int> openContentStream(ArchiveFile contentFileEntry) {
    final List<int> contentStream = <int>[];
    if (contentFileEntry.content == null) {
      throw EpubMissingArchiveEntryException(
          'Incorrect EPUB file: content file "$fileName" specified in manifest is not found.');
    }
    contentStream.addAll(contentFileEntry.content);
    return contentStream;
  }

  Future<Uint8List> readContentAsBytes() async {
    final ArchiveFile contentFileEntry = getContentFileEntry();
    final List<int> content = openContentStream(contentFileEntry);
    return Uint8List.fromList(content);
  }

  Future<String> readContentAsText() async {
    final List<int> contentStream = getContentStream();
    final String result = convert.utf8.decode(contentStream);
    return result;
  }
}
