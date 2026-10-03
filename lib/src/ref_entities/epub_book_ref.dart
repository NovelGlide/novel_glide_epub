import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart';
import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import '../entities/epub_schema.dart';
import '../epub_exception.dart';
import '../readers/book_cover_reader.dart';
import '../readers/chapter_reader.dart';
import '../utils/container_index.dart';
import '../utils/content_bytes.dart';
import 'epub_chapter_ref.dart';
import 'epub_content_ref.dart';

class EpubBookRef {
  const EpubBookRef({
    required Archive epubArchive,
    required this.title,
    required this.authorList,
    required this.schema,
    required this.content,
  }) : _epubArchive = epubArchive;

  final Archive _epubArchive;

  /// The first `dc:title`; empty when the package has none, although OPF
  /// requires one.
  final String title;

  /// Every `dc:creator`'s text, in document order; empty when the package
  /// names no creator. How the names are joined for display is the caller's
  /// decision.
  final List<String> authorList;
  final EpubSchema schema;
  final EpubContentRef content;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      title.hashCode,
      schema.hashCode,
      content.hashCode,
      ...authorList.map((String author) => author.hashCode),
    ];
    return hashObjects(objects);
  }

  @override
  bool operator ==(Object other) {
    if (other is! EpubBookRef) {
      return false;
    }

    return title == other.title &&
        schema == other.schema &&
        content == other.content &&
        collections.listsEqual(authorList, other.authorList);
  }

  /// The declared uncompressed size of each entry the book keeps, by its
  /// name in the archive.
  ///
  /// A book opened by `EpubReader` keeps `mimetype`, every `META-INF/`
  /// entry, the package document and every file its manifest lists that the
  /// archive holds. So that the table of contents is found regardless of
  /// case, it also keeps, for the package document and each file the
  /// manifest lists, the entry whose name differs from it only in case that
  /// comes first in the directory, under the name the archive gives it. It keeps no other: an entry
  /// [readEntry] finds by looking through the archive's directory is not
  /// added here. A size is the archive's own claim, not what the entry
  /// inflates to, which only a read of it tells. A book built over an
  /// [Archive] of the caller's has the size of each of its files.
  ///
  /// Each access builds a new map from the entries the book keeps; a caller
  /// that looks at it repeatedly keeps the map.
  Map<String, int> get knownEntrySizes =>
      Map<String, int>.unmodifiable(<String, int>{
        for (final ArchiveFile file in _epubArchive.files) file.name: file.size
      });

  /// The bytes of the archive entry named [name], whether or not the book's
  /// manifest lists it; null when the archive has no such entry.
  ///
  /// [name] is the entry's full name in the archive, as written there but
  /// with each `\` in a record's name read as a `/`, not relative to the
  /// package document and with no escapes decoded. An entry
  /// the book keeps is read at once. Any other is looked for in the
  /// archive's central directory, read through once more, record by record;
  /// one found is kept from then on, so the next read of it is direct, and a
  /// name the archive does not hold is looked for again each time.
  ///
  /// Each read inflates the entry anew, held to the `maxEntryBytes` the book
  /// was opened with and, when [maxBytes] is given, to the tighter of the
  /// two: the read is stopped part-way with [EpubArchiveTooLargeException]
  /// as soon as the entry inflates past it. A damaged entry fails with
  /// [EpubCorruptArchiveException], and one compressed with a method an
  /// EPUB may not use with [EpubUnsupportedCompressionException]. A
  /// [maxBytes] below zero throws [ArgumentError].
  ///
  /// A book built over an [Archive] of the caller's has no `maxEntryBytes`:
  /// [maxBytes] is the only limit on a read of it, and without one nothing
  /// bounds the read but the file. The read returns a copy of the bytes
  /// `ArchiveFile.content` gives, a list or the stream of a file made with
  /// `ArchiveFile.stream`, and no bytes for a file made with no content.
  /// Their count is checked against [maxBytes] before any of them is copied,
  /// and a file holding more is refused with [EpubArchiveTooLargeException].
  ///
  /// That stops a read before it costs anything only for a file that already
  /// holds its bytes as a list, or one made with `ArchiveFile.stream`. For a
  /// file whose content `package:archive` produces when it is asked for,
  /// every file a `ZipDecoder` decodes, or one made with the plain
  /// `ArchiveFile(name, size, stream)` constructor, `ArchiveFile.content`
  /// itself inflates or reads the whole entry, with no limit, and keeps it:
  /// [maxBytes] can only refuse it afterwards. What `ArchiveFile.content`
  /// throws, the `FormatException` of a damaged deflated entry say, comes
  /// out of the read as it is, not as one of this package's exceptions. A
  /// caller reading files it does not trust opens them with
  /// `EpubReader.openBook` or `EpubReader.openBookFile`, whose reads are
  /// stopped part-way.
  Future<Uint8List?> readEntry(String name, {int? maxBytes}) async {
    if (maxBytes != null) {
      RangeError.checkNotNegative(maxBytes, 'maxBytes');
    }
    final Archive archive = _epubArchive;
    if (archive is ContainerIndex) {
      return archive.read(name, maxBytes);
    }
    final ArchiveFile? file = archive.findFile(name);
    return file == null ? null : _copyHeld(file, maxBytes);
  }

  /// A copy of the bytes [file], one of an [Archive] of the caller's, holds,
  /// their count checked against [maxBytes] before any of them is copied:
  /// before any is read, too, for a file holding a list or made with
  /// `ArchiveFile.stream`.
  static Uint8List _copyHeld(ArchiveFile file, int? maxBytes) {
    final ContentBytes? held = ContentBytes.of(file.content);
    final int length = held?.length ?? 0;
    if (maxBytes != null && length > maxBytes) {
      throw EpubArchiveTooLargeException('An entry holds $length bytes; the '
          'read allows it at most $maxBytes.');
    }
    return held == null ? Uint8List(0) : Uint8List.fromList(held.read());
  }

  Future<List<EpubChapterRef>> getChapters() async {
    return const ChapterReader().getChapters(this);
  }

  Future<Image?> readCover() async {
    return await const BookCoverReader().readBookCover(this);
  }

  Future<Uint8List?> readCoverBytes() async {
    return await const BookCoverReader().readBookCoverBytes(this);
  }
}
