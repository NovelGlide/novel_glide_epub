// In-memory EPUB fixture assembly, shared by the reader test suites.
//
// Every fixture is a synthetic archive built with `package:archive`'s
// `ZipEncoder` — the convention established by
// `navigation_reader_epub3_nav_path_test.dart`. Nothing is read from disk, so
// a test can never pass against a pre-existing file: seed ids and body text
// all carry the `NGE-SEED-` marker, which exists nowhere outside this suite.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as images;

/// Assembles an EPUB-shaped ZIP.
///
/// [opfPath] is the archive path written into `META-INF/container.xml`; it is
/// NOT added to [textEntries] automatically — pass the OPF itself in there, so
/// a test can deliberately build an archive whose declared root file is
/// missing.
///
/// Set [includeContainer] to false to omit `META-INF/container.xml`.
Uint8List buildEpubArchive({
  required String opfPath,
  Map<String, String> textEntries = const <String, String>{},
  Map<String, List<int>> binaryEntries = const <String, List<int>>{},
  bool includeContainer = true,
}) {
  const String mimetype = 'application/epub+zip';
  final Archive archive = Archive()
    ..addFile(
      ArchiveFile('mimetype', mimetype.length, mimetype.codeUnits)
        ..compress = false,
    );

  if (includeContainer) {
    archive.addFile(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<container version="1.0" '
            'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles>'
            '<rootfile full-path="$opfPath" '
            'media-type="application/oebps-package+xml"/>'
            '</rootfiles>'
            '</container>',
      ),
    );
  }

  textEntries.forEach((String name, String content) {
    archive.addFile(ArchiveFile.string(name, content));
  });
  binaryEntries.forEach((String name, List<int> content) {
    archive.addFile(ArchiveFile(name, content.length, content));
  });

  final List<int>? encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('ZipEncoder.encode returned null');
  }
  return Uint8List.fromList(encoded);
}

/// A real, decodable 2x2 PNG — `BookCoverReader.readBookCover` runs the bytes
/// through `images.decodeImage`, so a placeholder byte list would leave the
/// decode branch unexercised.
Uint8List seedPngBytes() {
  final images.Image image = images.Image(width: 2, height: 2);
  images.fill(image, color: images.ColorRgb8(12, 34, 56));
  return images.encodePng(image);
}

/// A minimal XHTML document; [marker] makes each fixture chapter identifiable
/// in assertions.
String seedXhtml(String marker) => '<?xml version="1.0" encoding="UTF-8"?>'
    '<html xmlns="http://www.w3.org/1999/xhtml">'
    '<head><title>$marker</title></head>'
    '<body><p>$marker</p></body>'
    '</html>';
