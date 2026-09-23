import 'dart:async';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart' show IterableExtension;

import 'entities/epub_book.dart';
import 'entities/epub_byte_content_file.dart';
import 'entities/epub_chapter.dart';
import 'entities/epub_content.dart';
import 'entities/epub_content_file.dart';
import 'entities/epub_schema.dart';
import 'entities/epub_text_content_file.dart';
import 'readers/content_reader.dart';
import 'readers/schema_reader.dart';
import 'ref_entities/epub_book_ref.dart';
import 'ref_entities/epub_byte_content_file_ref.dart';
import 'ref_entities/epub_chapter_ref.dart';
import 'ref_entities/epub_content_file_ref.dart';
import 'ref_entities/epub_content_ref.dart';
import 'ref_entities/epub_text_content_file_ref.dart';
import 'schema/opf/epub_metadata.dart';
import 'schema/opf/epub_metadata_creator.dart';
import 'utils/unmodifiable_iterable.dart';

/// The primary interface for reading an EPUB file.
///
/// [openBook] loads the structure and text metadata only, leaving each content
/// file to be read on demand; [readBook] loads the whole book into memory.
/// This package's entry point, called by name from the NovelGlide app.
///
/// ```dart
/// // Read the basic metadata.
/// EpubBookRef epub = await const EpubReader().openBook(epubFileBytes);
/// // Extract values of interest.
/// String title = epub.title;
/// List<String> authors = epub.authorList;
/// EpubMetadata metadata = epub.schema.package.metadata;
/// String genres = metadata.subjects.join(', ');
/// ```
class EpubReader {
  const EpubReader();

  /// Loads basics metadata.
  ///
  /// Opens the book asynchronously without reading its main content.
  /// Holds the handle to the EPUB file.
  ///
  /// Argument [bytes] should be the bytes of
  /// the epub file you have loaded with something like the [dart:io] package's
  /// [readAsBytes()].
  ///
  /// This is a fast and convenient way to get the most important information
  /// about the book, notably the [EpubBookRef.title] and
  /// [EpubBookRef.authorList]. Additional information is loaded in the
  /// [EpubBookRef.schema] property such as the Epub version, publishers,
  /// languages and more.
  Future<EpubBookRef> openBook(FutureOr<List<int>> bytes) async {
    List<int> loadedBytes;
    if (bytes is Future) {
      loadedBytes = await bytes;
    } else {
      loadedBytes = bytes;
    }

    final Archive epubArchive = ZipDecoder().decodeBytes(loadedBytes);
    final EpubSchema schema =
        await const SchemaReader().readSchema(epubArchive);
    final EpubMetadata metadata = schema.package.metadata;
    return EpubBookRef(
      epubArchive: epubArchive,
      schema: schema,
      title: metadata.titles.firstOrNull ?? '',
      authorList: metadata.creators
          .map((EpubMetadataCreator creator) => creator.creator)
          .toUnmodifiableList(),
      content: const ContentReader().parseContentMap(
          epubArchive, schema.contentDirectoryPath, schema.package.manifest),
    );
  }

  /// Opens the book asynchronously and reads all of its content into the memory. Does not hold the handle to the EPUB file.
  Future<EpubBook> readBook(FutureOr<List<int>> bytes) async {
    List<int> loadedBytes;
    if (bytes is Future) {
      loadedBytes = await bytes;
    } else {
      loadedBytes = bytes;
    }

    final EpubBookRef epubBookRef = await openBook(loadedBytes);
    return EpubBook(
      schema: epubBookRef.schema,
      title: epubBookRef.title,
      authorList: epubBookRef.authorList,
      content: await readContent(epubBookRef.content),
      coverImage: await epubBookRef.readCover(),
      chapters: (await readChapters(await epubBookRef.getChapters()))
          .toUnmodifiableList(),
    );
  }

  Future<EpubContent> readContent(EpubContentRef contentRef) async {
    final Map<String, EpubTextContentFile> html =
        await readTextContentFiles(contentRef.html);
    final Map<String, EpubTextContentFile> css =
        await readTextContentFiles(contentRef.css);
    final Map<String, EpubByteContentFile> images =
        await readByteContentFiles(contentRef.images);
    final Map<String, EpubByteContentFile> fonts =
        await readByteContentFiles(contentRef.fonts);
    final Map<String, EpubContentFile> allFiles = <String, EpubContentFile>{
      ...html,
      ...css,
      ...images,
      ...fonts,
    };
    // The files with no bucket of their own, NCX and other XML included, are
    // read as bytes.
    for (final MapEntry<String, EpubContentFileRef> entry
        in contentRef.allFiles.entries) {
      if (!allFiles.containsKey(entry.key)) {
        allFiles[entry.key] = await readByteContentFile(entry.value);
      }
    }

    return EpubContent(
      html: Map<String, EpubTextContentFile>.unmodifiable(html),
      css: Map<String, EpubTextContentFile>.unmodifiable(css),
      images: Map<String, EpubByteContentFile>.unmodifiable(images),
      fonts: Map<String, EpubByteContentFile>.unmodifiable(fonts),
      allFiles: Map<String, EpubContentFile>.unmodifiable(allFiles),
    );
  }

  Future<Map<String, EpubTextContentFile>> readTextContentFiles(
      Map<String, EpubTextContentFileRef> textContentFileRefs) async {
    final Map<String, EpubTextContentFile> result =
        <String, EpubTextContentFile>{};
    for (final MapEntry<String, EpubTextContentFileRef> entry
        in textContentFileRefs.entries) {
      final EpubContentFileRef value = entry.value;
      result[entry.key] = EpubTextContentFile(
        fileName: value.fileName,
        contentType: value.contentType,
        contentMimeType: value.contentMimeType,
        content: await value.readContentAsText(),
      );
    }
    return result;
  }

  Future<Map<String, EpubByteContentFile>> readByteContentFiles(
      Map<String, EpubByteContentFileRef> byteContentFileRefs) async {
    final Map<String, EpubByteContentFile> result =
        <String, EpubByteContentFile>{};
    for (final MapEntry<String, EpubByteContentFileRef> entry
        in byteContentFileRefs.entries) {
      result[entry.key] = await readByteContentFile(entry.value);
    }
    return result;
  }

  Future<EpubByteContentFile> readByteContentFile(
      EpubContentFileRef contentFileRef) async {
    return EpubByteContentFile(
      fileName: contentFileRef.fileName,
      contentType: contentFileRef.contentType,
      contentMimeType: contentFileRef.contentMimeType,
      content: await contentFileRef.readContentAsBytes(),
    );
  }

  Future<List<EpubChapter>> readChapters(
      List<EpubChapterRef> chapterRefs) async {
    final List<EpubChapter> result = <EpubChapter>[];
    for (final EpubChapterRef chapterRef in chapterRefs) {
      result.add(EpubChapter(
        title: chapterRef.title,
        contentFileName: chapterRef.contentFileName,
        anchor: chapterRef.anchor,
        htmlContent: await chapterRef.readHtmlContent(),
        subChapters:
            (await readChapters(chapterRef.subChapters)).toUnmodifiableList(),
        otherContentFileNames: chapterRef.otherContentFileNames,
      ));
    }
    return result;
  }
}
