import 'dart:async';
import 'dart:io' show File, RawZLibFilter;
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart' show IterableExtension;

import 'entities/epub_book.dart';
import 'entities/epub_byte_content_file.dart';
import 'entities/epub_chapter.dart';
import 'entities/epub_content.dart';
import 'entities/epub_content_file.dart';
import 'entities/epub_schema.dart';
import 'entities/epub_text_content_file.dart';
import 'epub_exception.dart';
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
/// [openBookFile] and [readBookFile] do the same for a file on disk.
/// This package's entry point, called by name from the NovelGlide app.
///
/// Every entry point refuses, with [EpubArchiveTooLargeException], a ZIP
/// container past the limits below. The limits are fixed rather than
/// configurable, so there is no way to open a book without them.
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

  static const int _maxCompressedBytes = 512 * 1024 * 1024;
  static const int _maxEntries = 4096;
  static const int _maxEntryBytes = 256 * 1024 * 1024;
  static const int _maxTotalBytes = 512 * 1024 * 1024;
  static const int _inflateInputChunkBytes = 64 * 1024;

  /// Loads basics metadata.
  ///
  /// Opens the book asynchronously without parsing its content files.
  /// Holds the handle to the EPUB file.
  ///
  /// Argument [bytes] should be the bytes of the epub file; for a file on
  /// disk, [openBookFile] checks its size before reading it.
  ///
  /// Every entry of the archive is inflated here, once, within the limits
  /// [EpubReader] sets, and held in memory; a content file is read from its
  /// inflated entry on demand, without inflating it again.
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

    final Archive epubArchive = _decodeArchive(loadedBytes);
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

  /// [openBook] for the EPUB file at [path].
  ///
  /// The file's size is checked before any of it is read, so a file past the
  /// compressed-size limit is refused with [EpubArchiveTooLargeException]
  /// without being loaded into memory.
  Future<EpubBookRef> openBookFile(String path) async {
    return openBook(await _readArchiveFile(path));
  }

  /// [readBook] for the EPUB file at [path], with the size check
  /// [openBookFile] makes.
  Future<EpubBook> readBookFile(String path) async {
    return readBook(await _readArchiveFile(path));
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

  static Future<Uint8List> _readArchiveFile(String path) async {
    final File file = File(path);
    final int size = await file.length();
    _checkCompressedSize(size);

    // Read up to the length just checked and no further, so a file that grows
    // between the check and the read is not read past the limit.
    final Uint8List bytes = Uint8List(size);
    int filled = 0;
    await for (final List<int> chunk in file.openRead(0, size)) {
      bytes.setAll(filled, chunk);
      filled += chunk.length;
    }
    return Uint8List.sublistView(bytes, 0, filled);
  }

  /// Decodes [bytes] as a ZIP archive whose every entry is already inflated.
  ///
  /// The central directory's declared sizes and entry count are checked
  /// before anything is inflated. They are the archive's own claim, which a
  /// decompression bomb lies in, and which some writers get wrong in good
  /// faith (`package:archive`'s `ArchiveFile.string` declares a text's UTF-16
  /// length, short of its UTF-8 bytes). So each entry is then inflated
  /// counting the bytes it really produces, and abandoned as soon as they
  /// cross a limit.
  static Archive _decodeArchive(List<int> bytes) {
    _checkCompressedSize(bytes.length);
    final List<ZipFileHeader> headers =
        ZipDirectory.read(InputStream(bytes)).fileHeaders;
    _checkDirectory(headers);

    final Archive archive = Archive();
    int total = 0;
    for (final ZipFileHeader header in headers) {
      // `file` is null only on a header built without its input stream,
      // which `ZipDirectory.read` never does.
      if (header.file case final ZipFile file) {
        final List<int>? content =
            _inflateEntry(file, min(_maxEntryBytes, _maxTotalBytes - total));
        total += content?.length ?? 0;
        archive.addFile(content == null
            // No inflater here for this compression method, so the entry is
            // kept undecoded: reading it throws ArchiveException, inflating
            // nothing.
            ? ArchiveFile(file.filename, header.uncompressedSize ?? 0, file,
                file.compressionMethod)
            : ArchiveFile(file.filename, content.length, content));
      }
    }
    return archive;
  }

  static void _checkCompressedSize(int size) {
    if (size > _maxCompressedBytes) {
      throw EpubArchiveTooLargeException(
          'The file is $size bytes; the limit is $_maxCompressedBytes.');
    }
  }

  static void _checkDirectory(List<ZipFileHeader> headers) {
    if (headers.length > _maxEntries) {
      throw EpubArchiveTooLargeException('The archive has ${headers.length} '
          'entries; the limit is $_maxEntries.');
    }
    int total = 0;
    for (final ZipFileHeader header in headers) {
      final int declared = header.uncompressedSize ?? 0;
      if (declared > _maxEntryBytes) {
        throw EpubArchiveTooLargeException('An entry declares $declared '
            'bytes; the limit is $_maxEntryBytes.');
      }
      total += declared;
    }
    if (total > _maxTotalBytes) {
      throw EpubArchiveTooLargeException('The entries declare $total bytes '
          'in total; the limit is $_maxTotalBytes.');
    }
  }

  /// [file]'s content, inflated into at most [limit] bytes; null when there
  /// is no inflater here for its compression method.
  ///
  /// The ZIP encryption flag is not honoured: the EPUB container format
  /// forbids ZIP encryption, and decrypting without a password would only
  /// produce other bytes to inflate.
  static List<int>? _inflateEntry(ZipFile file, int limit) {
    switch ((file.compressionMethod, file.rawContent)) {
      case (ZipFile.zipCompressionStore, final InputStreamBase raw):
        final Uint8List stored = raw.toUint8List();
        _checkInflatedSize(stored.length, limit);
        return stored;
      case (ZipFile.zipCompressionDeflate, final InputStreamBase raw):
        return _inflateDeflate(raw.toUint8List(), limit);
      case (ZipFile.zipCompressionBZip2, final InputStreamBase raw):
        final _ArchiveEntryOutputStream output =
            _ArchiveEntryOutputStream(limit);
        BZip2Decoder().decodeStream(raw, output);
        return output.getBytes();
      default:
        return null;
    }
  }

  /// Inflates the raw-deflate stream [compressed] into at most [limit]
  /// bytes, a chunk of input at a time.
  ///
  /// zlib inflates only as far as each `processed` call asks, 64 KiB at a
  /// time, and each call returns all the output the input so far allows, so
  /// no end-of-stream call is needed to collect the rest. The chunks are kept
  /// as they come and joined once at the end, so an entry refused part-way
  /// never costs more than [limit], and one within it is copied only once.
  /// A corrupt stream throws `FormatException`.
  static Uint8List _inflateDeflate(Uint8List compressed, int limit) {
    final RawZLibFilter filter = RawZLibFilter.inflateFilter(raw: true);
    final BytesBuilder inflated = BytesBuilder(copy: false);
    for (int start = 0;
        start < compressed.length;
        start += _inflateInputChunkBytes) {
      filter.process(compressed, start,
          min(start + _inflateInputChunkBytes, compressed.length));
      for (List<int>? chunk = filter.processed();
          chunk != null;
          chunk = filter.processed()) {
        _checkInflatedSize(inflated.length + chunk.length, limit);
        inflated.add(chunk);
      }
    }
    return inflated.takeBytes();
  }

  static void _checkInflatedSize(int size, int limit) {
    if (size > limit) {
      throw EpubArchiveTooLargeException('An entry inflates to at least '
          '$size bytes; the per-entry and whole-archive limits leave it '
          '$limit.');
    }
  }
}

/// A BZIP2 entry's inflated content, refusing to grow past [_limit] bytes,
/// so that an entry past a limit is abandoned part-way through inflating
/// rather than after.
///
/// `BZip2Decoder` writes through [writeByte] only, so that is the one
/// bounded.
class _ArchiveEntryOutputStream extends OutputStream {
  _ArchiveEntryOutputStream(this._limit);

  final int _limit;

  @override
  void writeByte(int value) {
    EpubReader._checkInflatedSize(length + 1, _limit);
    super.writeByte(value);
  }
}
