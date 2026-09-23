import 'dart:async';
import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:quiver/core.dart';

import '../entities/epub_content_type.dart';
import '../epub_exception.dart';
import '../utils/zip_path_resolver.dart';

/// One manifest file, read from the archive on demand.
abstract class EpubContentFileRef {
  const EpubContentFileRef({
    required Archive epubArchive,
    required String contentDirectoryPath,
    required this.fileName,
    required this.contentType,
    required this.contentMimeType,
  })  : _epubArchive = epubArchive,
        _contentDirectoryPath = contentDirectoryPath;

  final Archive _epubArchive;

  /// The package document's directory, which [fileName] is relative to.
  final String _contentDirectoryPath;

  /// The manifest href with its percent-escapes decoded, relative to the
  /// package document's directory.
  final String fileName;
  final EpubContentType contentType;
  final String contentMimeType;

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
    final String contentFilePath =
        const ZipPathResolver().combine(_contentDirectoryPath, fileName);
    final ArchiveFile? contentFileEntry = _epubArchive.files
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
