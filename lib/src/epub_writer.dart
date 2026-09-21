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
/// [writeBook] is static on purpose, mirroring [EpubReader]: it is this
/// package's write-side entry point and is called by name from outside. The
/// assembly it delegates to is an ordinary instance method, so the type is a
/// unit with a static convenience entry rather than a namespace.
class EpubWriter {
  const EpubWriter();

  static const String _container_file =
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
    arch.addFile(ArchiveFile('META-INF/container.xml', _container_file.length,
        convert.utf8.encode(_container_file)));

    // Add all content to the archive
    book.Content!.AllFiles!.forEach((String name, EpubContentFile file) {
      List<int>? content;

      if (file is EpubByteContentFile) {
        content = file.Content;
      } else if (file is EpubTextContentFile) {
        content = convert.utf8.encode(file.Content!);
      }

      arch.addFile(ArchiveFile(
          _pathResolver.combine(book.Schema!.ContentDirectoryPath, name)!,
          content!.length,
          content));
    });

    // Generate the content.opf file and add it to the Archive
    final String contentopf = _packageWriter.writeContent(book.Schema!.Package!);

    arch.addFile(ArchiveFile(
        _pathResolver.combine(
            book.Schema!.ContentDirectoryPath, 'content.opf')!,
        contentopf.length,
        convert.utf8.encode(contentopf)));

    return arch;
  }

  // Serializes the EpubBook into a byte array
  static List<int>? writeBook(EpubBook book) =>
      ZipEncoder().encode(const EpubWriter()._createArchive(book));
}
