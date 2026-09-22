import 'dart:async';

import 'package:archive/archive.dart';

import 'entities/epub_book.dart';
import 'entities/epub_byte_content_file.dart';
import 'entities/epub_chapter.dart';
import 'entities/epub_content.dart';
import 'entities/epub_content_file.dart';
import 'entities/epub_text_content_file.dart';
import 'readers/content_reader.dart';
import 'readers/schema_reader.dart';
import 'ref_entities/epub_book_ref.dart';
import 'ref_entities/epub_byte_content_file_ref.dart';
import 'ref_entities/epub_chapter_ref.dart';
import 'ref_entities/epub_content_file_ref.dart';
import 'ref_entities/epub_content_ref.dart';
import 'ref_entities/epub_text_content_file_ref.dart';
import 'schema/opf/epub_metadata_creator.dart';

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
/// String author = epub.author;
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
  /// about the book, notably the [title], [author] and [authorList].
  /// Additional information is loaded in the [schema] property such as the
  /// Epub version, publishers, languages and more.
  Future<EpubBookRef> openBook(FutureOr<List<int>> bytes) async {
    List<int> loadedBytes;
    if (bytes is Future) {
      loadedBytes = await bytes;
    } else {
      loadedBytes = bytes;
    }

    final Archive epubArchive = ZipDecoder().decodeBytes(loadedBytes);

    final EpubBookRef bookRef = EpubBookRef(epubArchive);
    bookRef.schema = await const SchemaReader().readSchema(epubArchive);
    bookRef.title = bookRef.schema!.package!.metadata!.titles!
        .firstWhere((String name) => true, orElse: () => '');
    bookRef.authorList = bookRef.schema!.package!.metadata!.creators!
        .map((EpubMetadataCreator creator) => creator.creator)
        .toList();
    bookRef.author = bookRef.authorList!.join(', ');
    bookRef.content = const ContentReader().parseContentMap(bookRef);
    return bookRef;
  }

  /// Opens the book asynchronously and reads all of its content into the memory. Does not hold the handle to the EPUB file.
  Future<EpubBook> readBook(FutureOr<List<int>> bytes) async {
    final EpubBook result = EpubBook();
    List<int> loadedBytes;
    if (bytes is Future) {
      loadedBytes = await bytes;
    } else {
      loadedBytes = bytes;
    }

    final EpubBookRef epubBookRef = await openBook(loadedBytes);
    result.schema = epubBookRef.schema;
    result.title = epubBookRef.title;
    result.authorList = epubBookRef.authorList;
    result.author = epubBookRef.author;
    result.content = await readContent(epubBookRef.content!);
    result.coverImage = await epubBookRef.readCover();
    final List<EpubChapterRef> chapterRefs = await epubBookRef.getChapters();
    result.chapters = await readChapters(chapterRefs);

    return result;
  }

  Future<EpubContent> readContent(EpubContentRef contentRef) async {
    final EpubContent result = EpubContent();
    result.html = await readTextContentFiles(contentRef.html!);
    result.css = await readTextContentFiles(contentRef.css!);
    result.images = await readByteContentFiles(contentRef.images!);
    result.fonts = await readByteContentFiles(contentRef.fonts!);
    result.allFiles = <String, EpubContentFile>{};

    result.html!.forEach((String? key, EpubTextContentFile value) {
      result.allFiles![key!] = value;
    });
    result.css!.forEach((String? key, EpubTextContentFile value) {
      result.allFiles![key!] = value;
    });

    result.images!.forEach((String? key, EpubByteContentFile value) {
      result.allFiles![key!] = value;
    });
    result.fonts!.forEach((String? key, EpubByteContentFile value) {
      result.allFiles![key!] = value;
    });

    await Future.forEach(contentRef.allFiles!.keys, (String key) async {
      if (!result.allFiles!.containsKey(key)) {
        result.allFiles![key] =
            await readByteContentFile(contentRef.allFiles![key]!);
      }
    });

    return result;
  }

  Future<Map<String, EpubTextContentFile>> readTextContentFiles(
      Map<String, EpubTextContentFileRef> textContentFileRefs) async {
    final Map<String, EpubTextContentFile> result =
        <String, EpubTextContentFile>{};

    await Future.forEach(textContentFileRefs.keys, (String key) async {
      final EpubContentFileRef value = textContentFileRefs[key]!;
      final EpubTextContentFile textContentFile = EpubTextContentFile();
      textContentFile.fileName = value.fileName;
      textContentFile.contentType = value.contentType;
      textContentFile.contentMimeType = value.contentMimeType;
      textContentFile.content = await value.readContentAsText();
      result[key] = textContentFile;
    });
    return result;
  }

  Future<Map<String, EpubByteContentFile>> readByteContentFiles(
      Map<String, EpubByteContentFileRef> byteContentFileRefs) async {
    final Map<String, EpubByteContentFile> result =
        <String, EpubByteContentFile>{};
    await Future.forEach(byteContentFileRefs.keys, (String key) async {
      result[key] = await readByteContentFile(byteContentFileRefs[key]!);
    });
    return result;
  }

  Future<EpubByteContentFile> readByteContentFile(
      EpubContentFileRef contentFileRef) async {
    final EpubByteContentFile result = EpubByteContentFile();

    result.fileName = contentFileRef.fileName;
    result.contentType = contentFileRef.contentType;
    result.contentMimeType = contentFileRef.contentMimeType;
    result.content = await contentFileRef.readContentAsBytes();

    return result;
  }

  Future<List<EpubChapter>> readChapters(
      List<EpubChapterRef> chapterRefs) async {
    final List<EpubChapter> result = <EpubChapter>[];
    await Future.forEach(chapterRefs, (EpubChapterRef chapterRef) async {
      final EpubChapter chapter = EpubChapter();

      chapter.title = chapterRef.title;
      chapter.contentFileName = chapterRef.contentFileName;
      chapter.anchor = chapterRef.anchor;
      chapter.htmlContent = await chapterRef.readHtmlContent();
      chapter.subChapters = await readChapters(chapterRef.subChapters!);

      result.add(chapter);
    });
    return result;
  }
}
