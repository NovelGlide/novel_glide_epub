import 'dart:convert' as convert;

import 'package:archive/archive.dart';

import 'entities/epub_book.dart';
import 'entities/epub_byte_content_file.dart';
import 'entities/epub_content_file.dart';
import 'entities/epub_text_content_file.dart';
import 'utils/zip_path_resolver.dart';
import 'writers/epub_package_writer.dart';

/// Serialises an [EpubBook] back into an EPUB container.
///
/// This package's write-side entry point, called by name from outside,
/// mirroring [EpubReader].
///
/// ```dart
/// List<int>? bytes = const EpubWriter().writeBook(book);
/// ```
class EpubWriter {
  const EpubWriter();

  static const String _containerFile =
      '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>';

  ZipPathResolver get _pathResolver => const ZipPathResolver();
  EpubPackageWriter get _packageWriter => const EpubPackageWriter();

  // Creates a Zip Archive of an EpubBook
  Archive _createArchive(EpubBook book) {
    final Archive arch = Archive();

    // Add simple metadata
    arch.addFile(ArchiveFile.noCompress(
        'mimetype', 20, convert.utf8.encode('application/epub+zip')));

    // Add Container file
    arch.addFile(ArchiveFile('META-INF/container.xml', _containerFile.length,
        convert.utf8.encode(_containerFile)));

    // Add all content to the archive
    book.content!.allFiles!.forEach((String name, EpubContentFile file) {
      List<int>? content;

      if (file is EpubByteContentFile) {
        content = file.content;
      } else if (file is EpubTextContentFile) {
        content = convert.utf8.encode(file.content!);
      }

      arch.addFile(ArchiveFile(
          _pathResolver.combine(book.schema!.contentDirectoryPath, name),
          content!.length,
          content));
    });

    // Generate the content.opf file and add it to the Archive
    final String contentopf =
        _packageWriter.writeContent(book.schema!.package!);

    arch.addFile(ArchiveFile(
        _pathResolver.combine(book.schema!.contentDirectoryPath, 'content.opf'),
        contentopf.length,
        convert.utf8.encode(contentopf)));

    return arch;
  }

  // Serializes the EpubBook into a byte array
  List<int>? writeBook(EpubBook book) =>
      ZipEncoder().encode(_createArchive(book));
}
