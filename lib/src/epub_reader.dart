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
/// [openBook] parses the structure and text metadata only, leaving each
/// content file to be read on demand, though the whole archive is inflated;
/// [readBook] also reads every content file.
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
  /// [EpubReader] sets, and held in memory with [bytes] for as long as the
  /// returned [EpubBookRef] is; a content file is read from its inflated
  /// entry on demand, without inflating it again. An entry that cannot be
  /// inflated fails this call, whether or not the book uses it.
  ///
  /// This is a convenient way to get the most important information
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
  /// The entry count, and the sizes the central directory declares, are
  /// checked before anything is inflated. The declared uncompressed sizes are
  /// the archive's own claim, which a decompression bomb lies in, and which
  /// some writers get wrong in good faith (`package:archive`'s
  /// `ArchiveFile.string` declares a text's UTF-16 length, short of its UTF-8
  /// bytes). So each entry is then inflated counting the bytes it really
  /// produces, and abandoned as soon as they cross a limit.
  ///
  /// The compressed bytes are counted the same way, as each entry is given
  /// them: an honest ZIP's entries each hold their own bytes, so together
  /// they fit in the file. More means entries overlap, and every entry is
  /// inflated here: one stream shared by thousands would be inflated
  /// thousands of times, a cost the output limits do not bound when the
  /// stream inflates to little or nothing.
  ///
  /// This is where a ZIP that fails to decode becomes
  /// [EpubCorruptArchiveException]: `package:archive` reports a malformed
  /// container, and zlib an invalid stream, as a `FormatException`.
  static Archive _decodeArchive(List<int> bytes) {
    _checkCompressedSize(bytes.length);
    try {
      final InputStream input = InputStream(bytes);
      final List<ZipFileHeader> headers = _readCentralDirectory(input);
      _checkDeclaredSizes(headers);

      final Archive archive = Archive();
      int total = 0;
      int consumed = 0;
      for (final ZipFileHeader header in headers) {
        header.readLocalFileHeader(input, null);
        final ZipFile file =
            header.file ?? (throw StateError('No ZipFile for a header'));
        final Uint8List raw =
            (file.rawContent ?? (throw StateError('No raw content')))
                .toUint8List();
        consumed += raw.length;
        if (consumed > bytes.length) {
          throw EpubArchiveTooLargeException('The entries hold $consumed '
              'compressed bytes between them, more than the file\'s '
              '${bytes.length}: they overlap.');
        }
        final Uint8List content = _inflateEntry(file.compressionMethod, raw,
            min(_maxEntryBytes, _maxTotalBytes - total));
        total += content.length;
        archive.addFile(ArchiveFile(file.filename, content.length, content));
      }
      return archive;
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
          EpubCorruptArchiveException(error.message), stackTrace);
    }
  }

  static void _checkCompressedSize(int size) {
    if (size > _maxCompressedBytes) {
      throw EpubArchiveTooLargeException(
          'The file is $size bytes; the limit is $_maxCompressedBytes.');
    }
  }

  /// The central directory's headers, built one record at a time, the one
  /// past [_maxEntries] refused before it is built.
  ///
  /// `package:archive` has no public way to find the directory short of
  /// `ZipDirectory.read`, which builds a header for every record before the
  /// count can be seen, reading until the directory's bytes run out whatever
  /// count the end record states. A record is 46 bytes at least and many may
  /// point at one entry, so a 512 MiB file holds millions of them. So the
  /// directory is found here as `ZipDirectory.read` finds it, and its records
  /// read with the same public `ZipFileHeader`.
  static List<ZipFileHeader> _readCentralDirectory(InputStream input) {
    final InputStream directory = _centralDirectoryOf(input);
    final List<ZipFileHeader> headers = <ZipFileHeader>[];
    while (
        !directory.isEOS && directory.readUint32() == ZipFileHeader.SIGNATURE) {
      if (headers.length == _maxEntries) {
        throw const EpubArchiveTooLargeException(
            'The archive has more than $_maxEntries entries.');
      }
      headers.add(ZipFileHeader(directory));
    }
    return headers;
  }

  /// The central directory, found as `ZipDirectory.read` finds it.
  static InputStream _centralDirectoryOf(InputStream input) {
    final int end = _endRecordOf(input);
    if (end < 0) {
      throw const EpubCorruptArchiveException(
          'No end-of-central-directory record: the file is not a ZIP.');
    }

    input.position = end + 4;
    final int disk = input.readUint16();
    input.skip(2);
    final int diskEntries = input.readUint16();
    input.skip(2);
    int size = input.readUint32();
    int offset = input.readUint32();
    // Any of these at its maximum means the zip64 record holds the real
    // values, when there is one.
    if (offset == 0xffffffff ||
        size == 0xffffffff ||
        diskEntries == 0xffff ||
        disk == 0xffff) {
      final int? record = _zip64EndRecordOf(input, end);
      if (record != null) {
        input.position = record + 40;
        size = input.readUint64();
        offset = input.readUint64();
      }
    }
    return InputStream(input.subset(offset, size).toUint8List());
  }

  /// Where the end-of-central-directory record is, found as
  /// `ZipDirectory.read` finds it: the last one, searching from the back.
  /// -1 when there is none.
  static int _endRecordOf(InputStream input) {
    int end = input.length - 5;
    while (end >= 0 &&
        _uint32At(input, end) != ZipDirectory.eocdLocatorSignature) {
      end--;
    }
    return end;
  }

  /// Where the zip64 end-of-central-directory record is, when the locator
  /// before the end record at [end] points at one.
  static int? _zip64EndRecordOf(InputStream input, int end) {
    final int locator = end - ZipDirectory.zip64EocdLocatorSize;
    if (locator < 0 ||
        _uint32At(input, locator) != ZipDirectory.zip64EocdLocatorSignature) {
      return null;
    }
    input.position = locator + 8;
    final int record = input.readUint64();
    return _uint32At(input, record) == ZipDirectory.zip64EocdSignature
        ? record
        : null;
  }

  static int _uint32At(InputStream input, int position) {
    input.position = position;
    return input.readUint32();
  }

  /// Refuses [headers] whose declared sizes are past the limits.
  ///
  /// Only an early refusal: a zip64 size is read as a signed 64-bit value,
  /// so a declared size can be negative and pull the total down. What
  /// bounds an entry is the count of the bytes it really inflates to.
  static void _checkDeclaredSizes(List<ZipFileHeader> headers) {
    int total = 0;
    for (final ZipFileHeader header in headers) {
      final int declared =
          header.uncompressedSize ?? (throw StateError('No uncompressed size'));
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

  /// An entry's [raw] bytes, stored or deflated by [method], inflated into
  /// at most [limit] bytes.
  ///
  /// An EPUB container may only store or deflate its entries (EPUB OCF), so
  /// any other compression method refuses the book.
  ///
  /// The ZIP encryption flag is not honoured: the EPUB container format
  /// forbids ZIP encryption, and decrypting without a password would only
  /// produce other bytes to inflate.
  static Uint8List _inflateEntry(int method, Uint8List raw, int limit) {
    switch (method) {
      case ZipFile.zipCompressionStore:
        _checkInflatedSize(raw.length, limit);
        return raw;
      case ZipFile.zipCompressionDeflate:
        return _inflateDeflate(raw, limit);
      default:
        throw EpubUnsupportedCompressionException('An entry uses ZIP '
            'compression method $method; an EPUB may only store or deflate.');
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
  /// A stream that is not valid deflate throws `FormatException`; one cut
  /// short yields what it holds, as `package:archive`'s own inflate does.
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
