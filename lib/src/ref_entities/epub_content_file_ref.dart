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

  /// This file's bytes, as [openContentStream] gives them.
  Uint8List getContentStream() {
    return openContentStream(getContentFileEntry());
  }

  /// [contentFileEntry]'s bytes: the ones `ArchiveFile` holds for it, not a
  /// copy. They are shared with every other read of the entry, so a caller
  /// that changes them copies them first.
  ///
  /// An entry this package decoded holds a `Uint8List`, returned as it is;
  /// one a caller built on a plain `List<int>` is copied into one, once.
  Uint8List openContentStream(ArchiveFile contentFileEntry) {
    final Object? content = contentFileEntry.content;
    return switch (content) {
      Uint8List() => content,
      List<int>() => Uint8List.fromList(content),
      _ => throw EpubMissingArchiveEntryException(
          'Incorrect EPUB file: content file "$fileName" specified in '
          'manifest is not found.'),
    };
  }

  /// This file's bytes, as [openContentStream] gives them.
  Future<Uint8List> readContentAsBytes() async {
    return getContentStream();
  }

  Future<String> readContentAsText() async {
    return convert.utf8.decode(getContentStream());
  }
}
