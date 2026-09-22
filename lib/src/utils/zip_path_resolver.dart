import 'dart:convert';

/// Resolves a path inside the EPUB's ZIP container.
///
/// Every path an EPUB names is relative to the document that names it, so
/// reading one means joining it onto the directory of the other; this is the
/// one place that join happens.
class ZipPathResolver {
  const ZipPathResolver();

  String getDirectoryPath(String filePath) {
    final int lastSlashIndex = filePath.lastIndexOf('/');
    if (lastSlashIndex == -1) {
      return '';
    } else {
      return filePath.substring(0, lastSlashIndex);
    }
  }

  /// The file name an `href` refers to: every `%XX` escape decoded, every
  /// other character kept as written.
  ///
  /// An `href` is a URL, so it may escape characters, but real EPUBs just as
  /// often write non-ASCII names raw. `Uri.decodeFull` throws on a raw
  /// non-ASCII character, which made every book with an unescaped `第一章.xhtml`
  /// fail to open; it also throws on a `%` not followed by two hex digits,
  /// which a literal file name such as `100%.xhtml` contains. Both are kept
  /// as written here.
  ///
  /// When the escapes decode to bytes that are not valid UTF-8 (`%FF`, or a
  /// multi-byte character cut short), the [href] is returned unchanged
  /// rather than with replacement characters: two such hrefs would otherwise
  /// decode to the same name, and an error naming `�` would hide the
  /// name the book actually wrote.
  String decodeHref(String href) {
    if (!href.contains('%')) {
      return href;
    }

    final List<int> bytes = <int>[];
    final List<int> source = utf8.encode(href);
    int index = 0;
    while (index < source.length) {
      final int? escaped =
          source[index] == _percent ? _hexByteAt(source, index + 1) : null;
      if (escaped != null) {
        bytes.add(escaped);
        index += 3;
      } else {
        bytes.add(source[index]);
        index += 1;
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return href;
    }
  }

  /// Joins [fileName] onto [directory] and resolves its `.` and `..`
  /// segments, giving the name of the entry in the ZIP archive.
  ///
  /// Both arguments are plain, already-decoded file names, and so is the
  /// result. ZIP entry names are stored as raw UTF-8, never percent-encoded,
  /// so this is deliberately string work and not `Uri` work: resolving the
  /// segments with `Uri.normalizePath` percent-encodes every non-ASCII
  /// character, and a book whose files are named `第一章.xhtml` then looks
  /// up `%E7%AC%AC%E4%B8%80%E7%AB%A0.xhtml` and fails to open.
  ///
  /// A `\` is read as a `/`. The EPUB spec only allows `/`, but books built
  /// on Windows write `\` in their hrefs, and reading it as anything else
  /// would leave those books unable to find a single file.
  String combine(String? directory, String? fileName) {
    final String name = fileName!;
    final String path =
        directory == null || directory == '' ? name : '$directory/$name';

    final List<String> segments = <String>[];
    for (final String segment in path.replaceAll(r'\', '/').split('/')) {
      if (segment == '..') {
        // A `..` with nothing left to climb is dropped: no entry lives
        // above the container root.
        if (segments.isNotEmpty) {
          segments.removeLast();
        }
      } else if (segment != '.' && segment.isNotEmpty) {
        segments.add(segment);
      }
    }
    return segments.join('/');
  }

  static const int _percent = 0x25;

  /// The byte spelled by the two hex digits at [start], or null when there
  /// are not two hex digits there.
  int? _hexByteAt(List<int> source, int start) {
    if (start + 1 >= source.length) {
      return null;
    }
    final int? high = _hexValue(source[start]);
    final int? low = _hexValue(source[start + 1]);
    if (high == null || low == null) {
      return null;
    }
    return high * 16 + low;
  }

  int? _hexValue(int char) {
    if (char >= 0x30 && char <= 0x39) {
      return char - 0x30;
    }
    if (char >= 0x41 && char <= 0x46) {
      return char - 0x41 + 10;
    }
    if (char >= 0x61 && char <= 0x66) {
      return char - 0x61 + 10;
    }
    return null;
  }
}
