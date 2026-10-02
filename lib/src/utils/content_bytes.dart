import 'package:archive/archive.dart';

/// The bytes an `ArchiveFile` holds, as its `content` gives them, with their
/// count known before any of them is read.
///
/// `ArchiveFile.content` is a list of bytes for a file made with them, or
/// for an entry this package inflated, and a stream for one made with
/// `ArchiveFile.stream`. Reading a stream's bytes may read them from where
/// it keeps them, so [length] is there to be checked first.
final class ContentBytes {
  ContentBytes._(this.length, this._read);

  /// The bytes [content] holds, or null when it holds none, as for a file
  /// made with no content.
  static ContentBytes? of(Object? content) => switch (content) {
        final List<int> bytes => ContentBytes._(bytes.length, () => bytes),
        final InputStreamBase stream =>
          ContentBytes._(stream.length, stream.toUint8List),
        _ => null,
      };

  /// How many bytes there are.
  final int length;

  final List<int> Function() _read;

  /// The bytes themselves: the list the file holds, or what is left of its
  /// stream, neither copied.
  List<int> read() => _read();
}
