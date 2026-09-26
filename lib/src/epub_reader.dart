import 'dart:async';
import 'dart:collection' show UnmodifiableListView;
import 'dart:io' show File, RandomAccessFile, RawZLibFilter;
import 'dart:math' show max, min;
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
/// content file to be inflated and read on demand; [readBook] also reads
/// every content file. [openBookFile] and [readBookFile] do the same for a
/// file on disk, reading it a chunk at a time.
/// This package's entry point, called by name from the NovelGlide app.
///
/// What this package guards is its own decompression. An entry is inflated
/// only when it is read, by one inflater holding it to fixed limits, which
/// refuses with [EpubArchiveTooLargeException] an entry, or a book's entries
/// between them, inflating past them. The limits are not configurable, so
/// there is no way to read a book without them. Opening a book reads its
/// ZIP directory and the documents it parses to open, and nothing else;
/// an entry that is damaged, too large, or compressed with a method an EPUB
/// may not use fails when it is read, not when the book is opened.
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

  /// What an entry is read and inflated in: a chunk of input, a chunk of
  /// output.
  static const int _chunkBytes = 64 * 1024;

  /// What a file is read in when `package:archive` reads a header from it a
  /// few bytes at a time: a page, so a header costs one small read.
  static const int _windowBytes = 4 * 1024;

  /// An end-of-central-directory record without its comment.
  static const int _endRecordLength = 22;

  /// Loads basics metadata.
  ///
  /// Opens the book asynchronously without parsing its content files.
  ///
  /// Argument [bytes] should be the bytes of the epub file; for a file on
  /// disk, [openBookFile] reads it without loading it whole. The returned
  /// [EpubBookRef] holds [bytes], and reads each content file from them when
  /// asked for it.
  ///
  /// This reads the ZIP container's directory and each entry's local
  /// header, and inflates only the container, package and navigation
  /// documents it parses. Every other entry is inflated when it is read,
  /// into memory, and kept for as long as the [EpubBookRef] lives; one never
  /// read is never inflated.
  ///
  /// This is a convenient way to get the most important information
  /// about the book, notably the [EpubBookRef.title] and
  /// [EpubBookRef.authorList]. Additional information is loaded in the
  /// [EpubBookRef.schema] property such as the Epub version, publishers,
  /// languages and more.
  Future<EpubBookRef> openBook(FutureOr<List<int>> bytes) async {
    return _openBook(_ArchiveBytesSource(await bytes));
  }

  Future<EpubBookRef> _openBook(_ArchiveSource source) async {
    final Archive epubArchive = _openContainer(source);
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
  ///
  /// Each entry the book holds is inflated once, by the same reads
  /// [openBook]'s [EpubBookRef] makes, so one past the limits, damaged, or
  /// compressed with a method an EPUB may not use fails this call.
  Future<EpubBook> readBook(FutureOr<List<int>> bytes) async {
    return _readBook(await openBook(bytes));
  }

  Future<EpubBook> _readBook(EpubBookRef epubBookRef) async {
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

  /// [openBook] for the EPUB file at [path], read from the file a chunk at a
  /// time, never loaded whole. Its size is checked before any of it is read.
  ///
  /// The returned [EpubBookRef] holds [path], not an open file: each content
  /// file is read by opening the file again, reading that entry, and closing
  /// it, so there is nothing to close afterwards. Each read is held to the
  /// same limits whatever the file holds by then. A file that is gone fails
  /// the read with `FileSystemException`; one cut short so that the entry is
  /// no longer in it, or changed so that the entry no longer inflates, fails
  /// it with [EpubCorruptArchiveException]; one changed so that the entry
  /// inflates past a limit fails it with [EpubArchiveTooLargeException].
  /// Bytes changed in place within the limits are read as they are then.
  Future<EpubBookRef> openBookFile(String path) async {
    return _openBook(_ArchiveFileSource(path));
  }

  /// [readBook] for the EPUB file at [path], read as [openBookFile] reads it.
  Future<EpubBook> readBookFile(String path) async {
    return _readBook(await openBookFile(path));
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

  /// The ZIP container in [source], its entries left to be inflated when
  /// they are read, by [_LazyZipFile].
  ///
  /// This reads the container's directory and each entry's local header,
  /// and no entry's data. The entry count, and the sizes the central
  /// directory declares, are checked here; the declared uncompressed sizes
  /// are the archive's own claim, which a decompression bomb lies in, so a
  /// read also counts the bytes an entry really produces.
  ///
  /// The compressed bytes each entry is given are counted from their local
  /// headers: a well-formed ZIP's entries each hold their own bytes, so
  /// together they fit in the file. More means entries overlap, which is a
  /// damaged container: one stream shared by thousands would be inflated
  /// thousands of times by a book read whole, a cost the output limits do
  /// not bound when the stream inflates to little or nothing.
  static Archive _openContainer(_ArchiveSource source) {
    return _decodingZip(() => source.read((_BoundedInputStream input) {
          final int fileLength = input.length;
          _checkCompressedSize(fileLength);
          final List<ZipFileHeader> headers = _readCentralDirectory(input);
          _checkDeclaredSizes(headers);

          final Archive archive = Archive();
          final _ArchiveReadTotal readTotal = _ArchiveReadTotal();
          int consumed = 0;
          for (final ZipFileHeader header in headers) {
            header.readLocalFileHeader(input, null);
            final ZipFile file =
                header.file ?? (throw StateError('No ZipFile for a header'));
            final _BoundedInputStream raw =
                file.rawContent as _BoundedInputStream;
            consumed += raw.length;
            if (consumed > fileLength) {
              throw EpubCorruptArchiveException('The entries hold $consumed '
                  'compressed bytes between them, more than the file\'s '
                  '$fileLength: they overlap.');
            }
            final int declared = header.uncompressedSize ?? 0;
            archive.addFile(ArchiveFile(
                file.filename,
                declared,
                _LazyZipFile(source, readTotal, raw.start, raw.length,
                    file.compressionMethod, declared)));
          }
          return archive;
        }));
  }

  /// [decode], with a ZIP that fails to decode turned into
  /// [EpubCorruptArchiveException]: `package:archive` reports a malformed
  /// container, and zlib an invalid stream, as a `FormatException`.
  static T _decodingZip<T>(T Function() decode) {
    try {
      return decode();
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
  /// directory is found here, and its records read with the same public
  /// `ZipFileHeader`.
  static List<ZipFileHeader> _readCentralDirectory(InputStream input) {
    final InputStreamBase directory = _centralDirectoryOf(input);
    final List<ZipFileHeader> headers = <ZipFileHeader>[];
    // Fewer than a signature's four bytes left are stray bytes after the
    // last record, not a record cut short.
    while (directory.length >= 4 &&
        directory.readUint32() == ZipFileHeader.SIGNATURE) {
      if (headers.length == _maxEntries) {
        throw const EpubArchiveTooLargeException(
            'The archive has more than $_maxEntries entries.');
      }
      headers.add(ZipFileHeader(directory));
    }
    return headers;
  }

  /// The central directory in the unread [input].
  static InputStreamBase _centralDirectoryOf(InputStream input) {
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
    return input.subset(offset, size);
  }

  /// Where the end-of-central-directory record is in the unread [input]: the
  /// last one, searching from the back from the last place a whole record
  /// fits. -1 when there is none.
  ///
  /// A record's comment follows it and may hold anything, its signature
  /// included; one in the comment's last bytes has no room for a record after
  /// it, so the search starts before it.
  static int _endRecordOf(InputStream input) {
    int end = input.length - _endRecordLength;
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

  /// An entry's [raw] bytes, stored or deflated by [method], inflated a
  /// chunk at a time into [_InflatedBytes] sized for [declaredSize], and
  /// refused as soon as the output passes [limit].
  ///
  /// The one inflater: every read of an entry goes through it. zlib inflates
  /// only as far as each `processed` call asks, 64 KiB at a time, and each
  /// call returns all the output the input so far allows, so no
  /// end-of-stream call is needed to collect the rest. A stream that is not
  /// valid deflate throws `FormatException`; one cut short yields what it
  /// holds, as `package:archive`'s own inflate does.
  ///
  /// An EPUB container may only store or deflate its entries (EPUB OCF), so
  /// any other compression method refuses the book. The ZIP encryption flag
  /// is not honoured: the EPUB container format forbids ZIP encryption, and
  /// decrypting without a password would only produce other bytes to
  /// inflate.
  static Uint8List _inflate(
      _BoundedInputStream raw, int method, int limit, int declaredSize) {
    final RawZLibFilter? inflater = switch (method) {
      ZipFile.zipCompressionStore => null,
      ZipFile.zipCompressionDeflate => RawZLibFilter.inflateFilter(raw: true),
      _ => throw EpubUnsupportedCompressionException('An entry uses ZIP '
          'compression method $method; an EPUB may only store or deflate.'),
    };
    final _InflatedBytes inflated =
        _InflatedBytes(min(max(0, declaredSize), limit));
    void take(List<int> chunk) {
      _checkInflatedSize(inflated.length + chunk.length, limit);
      inflated.add(chunk);
    }

    while (!raw.isEOS) {
      final List<int> chunk = raw._readChunk(_chunkBytes);
      if (inflater == null) {
        take(chunk);
      } else {
        inflater.process(chunk, 0, chunk.length);
        for (List<int>? output = inflater.processed();
            output != null;
            output = inflater.processed()) {
          take(output);
        }
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

/// An `InputStream` that refuses, as a damaged container, a read or a move
/// past the end of its bytes, and a negative length, before it happens.
///
/// `InputStream` checks no bounds: it reads past its end with a RangeError.
/// Every stream the container is read through, by `package:archive` or by
/// [EpubReader], opening a book or reading an entry, from bytes or a file, is
/// this one or derives from it by [subset], which `readBytes` and
/// `peekBytes` go through and which keeps returning this type. Its bytes are
/// a list: the caller's, or a [_FileBytes] reading an open file. The members
/// bounded are the ones `package:archive` 3.6.1's `ZipFileHeader` and
/// `ZipFile`, and [EpubReader], call on these streams; `readByte` and
/// `readUint24` are called by neither.
///
/// Two paths in `package:archive` copy bytes into an `InputStream` of their
/// own, which this does not reach: `ZipFileHeader` parses every
/// central-directory record's extra field, whatever its blocks, that way;
/// `ZipFile` parses a local header's extra field that way when the entry's
/// encryption flag is set and the field is longer than two bytes.
class _BoundedInputStream extends InputStream {
  _BoundedInputStream(List<int> super.data);

  _BoundedInputStream._of(super.other) : super.from();

  /// All the bytes this stream has, read or not.
  int get _size => position + length;

  @override
  set position(int v) {
    if (v < 0 || v > _size) {
      throw EpubCorruptArchiveException(
          'A ZIP structure points at $v, outside the $_size bytes it is in.');
    }
    super.position = v;
  }

  @override
  void skip(int count) {
    position = position + count;
  }

  @override
  int readUint16() {
    _require(2);
    return super.readUint16();
  }

  @override
  int readUint32() {
    _require(4);
    return super.readUint32();
  }

  @override
  int readUint64() {
    _require(8);
    return super.readUint64();
  }

  @override
  _BoundedInputStream subset([int? position, int? length]) {
    if (length != null && length < 0) {
      throw EpubCorruptArchiveException(
          'A ZIP structure has a negative length, $length.');
    }
    final InputStream part = super.subset(position, length) as InputStream;
    final int from = part.start - start;
    if (from < 0 || part.length < 0 || from > _size - part.length) {
      throw EpubCorruptArchiveException('A ZIP structure of ${part.length} '
          'bytes at $from lies outside the $_size bytes it is in.');
    }
    return _BoundedInputStream._of(part);
  }

  /// The next [max] bytes, or as many as are left.
  List<int> _readChunk(int max) {
    final int end = offset + min(max, length);
    final List<int> chunk = buffer.sublist(offset, end);
    offset = end;
    return chunk;
  }

  void _require(int count) {
    if (count > length) {
      throw EpubCorruptArchiveException('A ZIP structure needs $count bytes '
          'at $position, where $length are left.');
    }
  }
}

/// Where a container's bytes are, each time they are read.
sealed class _ArchiveSource {
  /// [read] run on a stream over the container's bytes as they are now.
  T read<T>(T Function(_BoundedInputStream input) read);
}

/// A container the caller holds in memory: its bytes are read in place.
final class _ArchiveBytesSource extends _ArchiveSource {
  _ArchiveBytesSource(this._bytes);

  final List<int> _bytes;

  @override
  T read<T>(T Function(_BoundedInputStream input) read) =>
      read(_BoundedInputStream(_bytes));
}

/// A container in a file, opened for each read and closed after it, so that
/// no handle outlives the call that needed it.
final class _ArchiveFileSource extends _ArchiveSource {
  _ArchiveFileSource(this._path);

  final String _path;

  @override
  T read<T>(T Function(_BoundedInputStream input) read) {
    final RandomAccessFile file = File(_path).openSync();
    try {
      return read(_BoundedInputStream(_FileBytes(file)));
    } finally {
      file.closeSync();
    }
  }
}

/// The bytes of an open [RandomAccessFile], as a list `InputStream` can read.
///
/// An index is read from a window of the file, loaded around it when it
/// falls outside, since `package:archive` reads a header a few bytes at a
/// time; a [sublist] is read from the file in one piece. The length is the
/// file's when this is made; a read that finds the file cut shorter since
/// refuses it as a damaged container.
final class _FileBytes extends UnmodifiableListView<int> {
  _FileBytes(this._file)
      : length = _file.lengthSync(),
        super(const <int>[]);

  final RandomAccessFile _file;

  @override
  final int length;

  int _windowStart = 0;
  Uint8List _window = Uint8List(0);

  @override
  int operator [](int index) {
    if (index < _windowStart || index >= _windowStart + _window.length) {
      _windowStart = max(0, index - EpubReader._windowBytes ~/ 2);
      _window = sublist(
          _windowStart, min(length, _windowStart + EpubReader._windowBytes));
    }
    return _window[index - _windowStart];
  }

  @override
  Uint8List sublist(int start, [int? end]) {
    final Uint8List bytes = Uint8List((end ?? length) - start);
    _file.setPositionSync(start);
    return _file.readIntoSync(bytes) == bytes.length ? bytes : throw _cut;
  }

  static const EpubCorruptArchiveException _cut =
      EpubCorruptArchiveException('The file is shorter than it was opened.');
}

/// What the entries of one container have inflated to between them, each
/// counted once, when it is read.
final class _ArchiveReadTotal {
  int bytes = 0;
}

/// An entry of a container, inflated from [_source] when `ArchiveFile` asks
/// for its content, which it asks for once and keeps.
///
/// A `ZipFile` because `ArchiveFile` leaves the content of a `ZipFile`, or
/// of anything else implementing `package:archive`'s unexported
/// `FileContent`, unread until it is asked for.
///
/// A read is held to the per-entry limit and to what [_readTotal] has left
/// of the whole-archive limit, and adds what it inflated to it. [_source] is
/// read as it is then, whatever it held when the book was opened.
final class _LazyZipFile extends ZipFile {
  _LazyZipFile(this._source, this._readTotal, this._start, this._length,
      this._method, this._declaredSize);

  final _ArchiveSource _source;
  final _ArchiveReadTotal _readTotal;
  final int _start;
  final int _length;
  final int _method;
  final int _declaredSize;

  @override
  InputStreamBase? get rawContent => null;

  @override
  List<int> get content => EpubReader._decodingZip(() => _source.read(
        (_BoundedInputStream input) {
          final Uint8List content = EpubReader._inflate(
              input.subset(_start, _length),
              _method,
              min(EpubReader._maxEntryBytes,
                  EpubReader._maxTotalBytes - _readTotal.bytes),
              _declaredSize);
          _readTotal.bytes += content.length;
          return content;
        },
      ));
}

/// An entry's inflated bytes, collected into a buffer of the size the entry
/// declares and, past that, as the inflater's chunks.
///
/// An honest entry is held once: inflated into its buffer, returned as it
/// is. The declared size may be wrong in either direction, in good faith
/// (`package:archive`'s `ArchiveFile.string` declares a text's UTF-16
/// length) or not, and the inflater's limit is what bounds the entry, so
/// the buffer is only a first guess. An entry inflating past it keeps its
/// chunks and is joined once at the end, holding it twice for that moment
/// at most; one inflating to less is copied out of it, so a buffer larger
/// than the entry is not kept. Nothing grows by reallocating.
final class _InflatedBytes {
  _InflatedBytes(int declaredSize) : _declared = Uint8List(declaredSize);

  final Uint8List _declared;
  int _filled = 0;
  BytesBuilder? _overflow;

  /// The bytes collected so far.
  int get length => _overflow?.length ?? _filled;

  void add(List<int> chunk) {
    final BytesBuilder? overflow = _overflow;
    if (overflow != null) {
      overflow.add(chunk);
    } else if (_filled + chunk.length <= _declared.length) {
      _declared.setAll(_filled, chunk);
      _filled += chunk.length;
    } else {
      _overflow = BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(_declared, 0, _filled))
        ..add(chunk);
    }
  }

  Uint8List takeBytes() =>
      _overflow?.takeBytes() ??
      (_filled == _declared.length
          ? _declared
          : Uint8List.fromList(Uint8List.sublistView(_declared, 0, _filled)));
}
