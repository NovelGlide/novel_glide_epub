// `EpubWriter` — the whole-archive serialiser — at the round-trip level.
//
// The shape that carries the most weight here is read → write → read: a book
// assembled by `buildEpubArchive`, loaded by `EpubReader.readBook`, written
// back out by `EpubWriter.writeBook`, and loaded again. `EpubBook.==` compares
// by value down to the chapter list and the decoded cover, so a single
// `expect(reread, original)` states that the serialiser lost nothing.
//
// Where it DOES lose something, the loss gets its own named test rather than
// being hidden behind a weaker assertion — see the `known losses` group.
import 'dart:convert' as convert;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/novel_glide_epub.dart';
import 'package:novel_glide_epub/src/readers/package_reader.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'support/epub_fixture.dart';

/// The OPF directory `EpubWriter` is hard-wired to (see TC-WRT-6); every
/// round-trip fixture has to use it or the rewritten container points at
/// nothing.
const String _contentDir = 'OEBPS';

const String _guide = '<guide>'
    '<reference type="toc" title="NGE-SEED Contents" href="chapter1.xhtml"/>'
    '</guide>';

const String _ncx = '<?xml version="1.0" encoding="UTF-8"?>'
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
    '<head><meta name="dtb:uid" content="NGE-SEED-ID"/></head>'
    '<docTitle><text>NGE-SEED Round Trip</text></docTitle>'
    '<navMap>'
    '<navPoint id="np-1" playOrder="1">'
    '<navLabel><text>NGE-SEED Chapter One</text></navLabel>'
    '<content src="chapter1.xhtml"/>'
    '</navPoint>'
    '</navMap>'
    '</ncx>';

/// An OPF exercising every metadata element, both content buckets and a guide.
///
/// [spineItemRef], [guide] and [extraManifestItems] are injected so a test
/// can vary the one part it is about without restating the other forty lines.
String _opf({
  String spineItemRef = '<itemref idref="ch1"/>',
  String guide = _guide,
  String extraManifestItems = '',
}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
    'unique-identifier="etextno">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" '
    'xmlns:opf="http://www.idpf.org/2007/opf">'
    '<dc:title>NGE-SEED Round Trip</dc:title>'
    '<dc:creator opf:role="aut" opf:file-as="SEED, NGE">NGE-SEED Author'
    '</dc:creator>'
    '<dc:subject>NGE-SEED Subject</dc:subject>'
    '<dc:description>NGE-SEED Description</dc:description>'
    '<dc:publisher>NGE-SEED Publisher</dc:publisher>'
    '<dc:contributor opf:role="edt" opf:file-as="SEED, Editor">'
    'NGE-SEED Contributor</dc:contributor>'
    '<dc:date>2026-09-21</dc:date>'
    '<dc:type>NGE-SEED Type</dc:type>'
    '<dc:format>NGE-SEED Format</dc:format>'
    '<dc:identifier id="etextno" opf:scheme="URI">NGE-SEED-ID</dc:identifier>'
    '<dc:source>NGE-SEED Source</dc:source>'
    '<dc:language>en</dc:language>'
    '<dc:relation>NGE-SEED Relation</dc:relation>'
    '<dc:coverage>NGE-SEED Coverage</dc:coverage>'
    '<dc:rights>NGE-SEED Rights</dc:rights>'
    '<meta name="cover" content="cover-image"/>'
    '</metadata>'
    '<manifest>'
    '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
    '<item id="ch1" href="chapter1.xhtml" '
    'media-type="application/xhtml+xml"/>'
    '<item id="css" href="style.css" media-type="text/css"/>'
    '<item id="cover-image" href="cover.png" media-type="image/png"/>'
    '$extraManifestItems'
    '</manifest>'
    '<spine toc="ncx">$spineItemRef</spine>'
    '$guide'
    '</package>';

Uint8List _seedArchive({
  String spineItemRef = '<itemref idref="ch1"/>',
  String guide = _guide,
  String extraManifestItems = '',
  Map<String, String> extraTextEntries = const <String, String>{},
}) =>
    buildEpubArchive(
      opfPath: '$_contentDir/content.opf',
      textEntries: <String, String>{
        '$_contentDir/content.opf': _opf(
            spineItemRef: spineItemRef,
            guide: guide,
            extraManifestItems: extraManifestItems),
        '$_contentDir/toc.ncx': _ncx,
        '$_contentDir/chapter1.xhtml': seedXhtml('NGE-SEED Chapter One'),
        '$_contentDir/style.css': 'p { color: #123456; } /* NGE-SEED */',
        ...extraTextEntries,
      },
      binaryEntries: <String, List<int>>{
        '$_contentDir/cover.png': seedPngBytes(),
      },
    );

/// An EPUB3 book in the shape EPUB3 allows and EPUB2 does not: a spine with
/// no `toc` attribute and a package with no `<guide>`, its table of contents
/// carried by a nav document instead of an NCX.
Uint8List _epub3ArchiveWithoutTocOrGuide() => buildEpubArchive(
      opfPath: '$_contentDir/content.opf',
      textEntries: <String, String>{
        '$_contentDir/content.opf': '<?xml version="1.0" encoding="UTF-8"?>'
            '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
            'unique-identifier="uid">'
            '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
            '<dc:identifier id="uid">urn:uuid:NGE-SEED-EPUB3</dc:identifier>'
            '<dc:title>NGE-SEED EPUB3</dc:title>'
            '<dc:language>en</dc:language>'
            '</metadata>'
            '<manifest>'
            '<item id="nav" href="nav.xhtml" '
            'media-type="application/xhtml+xml" properties="nav"/>'
            '<item id="ch1" href="chapter1.xhtml" '
            'media-type="application/xhtml+xml"/>'
            '</manifest>'
            '<spine><itemref idref="ch1"/></spine>'
            '</package>',
        '$_contentDir/nav.xhtml': '<?xml version="1.0" encoding="UTF-8"?>'
            '<html xmlns="http://www.w3.org/1999/xhtml" '
            'xmlns:epub="http://www.idpf.org/2007/ops">'
            '<head><title>NGE-SEED Navigation</title></head>'
            '<body><nav epub:type="toc"><ol>'
            '<li><a href="chapter1.xhtml">NGE-SEED Chapter One</a></li>'
            '</ol></nav></body>'
            '</html>',
        '$_contentDir/chapter1.xhtml': seedXhtml('NGE-SEED Chapter One'),
      },
    );

/// A content file of neither kind `EpubWriter` can serialise: the reader
/// never makes one, but `EpubContentFile` is open to subclassing.
class _UnknownContentFile extends EpubContentFile {
  const _UnknownContentFile()
      : super(
          fileName: 'NGE-SEED-unknown.bin',
          contentType: EpubContentType.other,
          contentMimeType: 'application/octet-stream',
        );
}

Future<EpubBook> _roundTrip(EpubBook book) async =>
    const EpubReader().readBook(const EpubWriter().writeBook(book)!);

Archive _writtenArchive(EpubBook book) =>
    ZipDecoder().decodeBytes(const EpubWriter().writeBook(book)!);

String _entryText(Archive archive, String name) => convert.utf8.decode(
    archive.files.firstWhere((ArchiveFile f) => f.name == name).content);

Iterable<String> _entryNames(Archive archive) =>
    archive.files.map((ArchiveFile f) => f.name);

/// [book] with every spine item's linearity flipped back — the one change a
/// trip makes to a book (TC-WRT-8), undone so the rest can be compared with
/// `==`.
EpubBook _withLinearityFlipped(EpubBook book) {
  final EpubPackage package = book.schema.package;
  return EpubBook(
    title: book.title,
    authorList: book.authorList,
    schema: EpubSchema(
      package: EpubPackage(
        version: package.version,
        metadata: package.metadata,
        manifest: package.manifest,
        spine: EpubSpine(
          tableOfContents: package.spine.tableOfContents,
          ltr: package.spine.ltr,
          items: <EpubSpineItemRef>[
            for (final EpubSpineItemRef item in package.spine.items)
              EpubSpineItemRef(idRef: item.idRef, isLinear: !item.isLinear),
          ],
        ),
        guide: package.guide,
      ),
      navigation: book.schema.navigation,
      contentDirectoryPath: book.schema.contentDirectoryPath,
    ),
    content: book.content,
    chapters: book.chapters,
    coverImage: book.coverImage,
  );
}

/// [book] holding [allFiles] as its content, everything else unchanged.
EpubBook _withAllFiles(EpubBook book, Map<String, EpubContentFile> allFiles) =>
    EpubBook(
      title: book.title,
      authorList: book.authorList,
      schema: book.schema,
      content: EpubContent(allFiles: allFiles),
      chapters: book.chapters,
      coverImage: book.coverImage,
    );

void main() {
  group('EpubWriter.writeBook round trip', () {
    // TC-WRT-1 [Scenario/use-case]: the headline claim — a book written out and
    // read back in is the same book, by `EpubBook.==`, which reaches the
    // schema, every content file, the decoded cover and the chapter tree.
    //
    // The one exception is spine linearity, which the reader/writer pair
    // inverts unconditionally (TC-WRT-8). Undoing that single flip is what
    // lets this assertion be `==` on the whole book rather than a weaker
    // field-by-field subset: anything ELSE the writer drops fails here.
    test('TC-WRT-1 [Scenario]: a written book reads back equal to the original',
        () async {
      final EpubBook original =
          await const EpubReader().readBook(_seedArchive());

      final EpubBook reread = await _roundTrip(original);

      expect(_withLinearityFlipped(reread), original);
    });

    // TC-WRT-2 [Scenario/use-case]: the same trip, asserted part by part, so a
    // regression names the part it broke instead of only saying "not equal".
    test('TC-WRT-2 [Scenario]: each part of the book survives independently',
        () async {
      final EpubBook original =
          await const EpubReader().readBook(_seedArchive());

      final EpubBook reread = await _roundTrip(original);

      expect(reread.title, original.title);
      expect(reread.authorList, original.authorList);
      expect(reread.schema.contentDirectoryPath,
          original.schema.contentDirectoryPath);
      expect(reread.schema.package.metadata, original.schema.package.metadata);
      expect(reread.schema.package.manifest, original.schema.package.manifest);
      expect(reread.schema.package.guide, original.schema.package.guide);
      expect(reread.schema.navigation, original.schema.navigation);
      expect(reread.content, original.content);
      expect(reread.chapters, original.chapters);
      expect(reread.coverImage!.getBytes(), original.coverImage!.getBytes());
    });

    // TC-WRT-9 [Scenario/use-case]: the parts of the spine that DO survive —
    // the `toc` idref, the reading direction and the item order — separated
    // from the linearity flag that does not.
    test('TC-WRT-9 [Scenario]: the spine keeps its toc, direction and order',
        () async {
      final EpubBook original = await const EpubReader().readBook(_seedArchive(
          spineItemRef: '<itemref idref="ch1"/><itemref idref="css"/>'));

      final EpubSpine spine = (await _roundTrip(original)).schema.package.spine;

      expect(spine.tableOfContents, 'ncx');
      expect(spine.ltr, isTrue);
      expect(spine.items.map((EpubSpineItemRef i) => i.idRef),
          <String>['ch1', 'css']);
    });

    // TC-WRT-7 [Equivalence partitioning]: a package with no `<guide>` — the
    // norm in EPUB 3 — is the other side of the guide partition. The writer
    // emits no element for it rather than an empty one, so the trip brings
    // back the same null guide and, flip undone, the same book.
    test('TC-WRT-7 [Equivalence]: a book with no guide round-trips without one',
        () async {
      final EpubBook original =
          await const EpubReader().readBook(_seedArchive(guide: ''));
      expect(original.schema.package.guide, isNull);

      final Archive archive = _writtenArchive(original);
      final EpubBook reread = await _roundTrip(original);

      expect(
          XmlDocument.parse(_entryText(archive, 'OEBPS/content.opf'))
              .rootElement
              .childElements
              .map((XmlElement e) => e.name.local),
          <String>['metadata', 'manifest', 'spine']);
      expect(reread.schema.package.guide, isNull);
      expect(_withLinearityFlipped(reread), original);
    });

    // TC-WRT-12 [Error guessing]: the content map is keyed by the DECODED
    // file name, which is the archive entry's name exactly, so the writer
    // must use the key as it stands. A file literally named `100%25.xhtml`
    // (manifest href `100%2525.xhtml`) is the case that tells the two apart:
    // decoding the key a second time would write it as `100%.xhtml`, an entry
    // the rewritten manifest does not name.
    test(
        'TC-WRT-12 [Error guessing]: a file name holding a literal %25 is '
        'written under that exact name', () async {
      final EpubBook original = await const EpubReader().readBook(_seedArchive(
        extraManifestItems: '<item id="pct" href="100%2525.xhtml" '
            'media-type="application/xhtml+xml"/>',
        extraTextEntries: <String, String>{
          '$_contentDir/100%25.xhtml': seedXhtml('NGE-SEED Percent'),
        },
      ));
      expect(original.content.allFiles.keys, contains('100%25.xhtml'));

      final Archive archive = _writtenArchive(original);
      final EpubBook reread = await _roundTrip(original);

      expect(_entryNames(archive), contains('OEBPS/100%25.xhtml'));
      expect(_entryNames(archive), isNot(contains('OEBPS/100%.xhtml')));
      expect(_entryText(archive, 'OEBPS/100%25.xhtml'),
          seedXhtml('NGE-SEED Percent'));
      expect(_withLinearityFlipped(reread), original);
    });
  });

  group('EpubWriter.writeBook archive layout', () {
    // TC-WRT-3 [Scenario/use-case]: the four kinds of entry the writer emits.
    test('TC-WRT-3 [Scenario]: emits mimetype, container, content and the OPF',
        () async {
      final EpubBook book = await const EpubReader().readBook(_seedArchive());

      final Archive archive = _writtenArchive(book);

      expect(
        _entryNames(archive),
        containsAll(<String>[
          'mimetype',
          'META-INF/container.xml',
          'OEBPS/content.opf',
          'OEBPS/toc.ncx',
          'OEBPS/chapter1.xhtml',
          'OEBPS/style.css',
          'OEBPS/cover.png',
        ]),
      );
    });

    // TC-WRT-4 [Boundary value]: `mimetype` must be stored uncompressed for the
    // archive to be a valid EPUB container.
    test('TC-WRT-4 [Boundary]: mimetype is stored uncompressed', () async {
      final EpubBook book = await const EpubReader().readBook(_seedArchive());

      final Archive archive = _writtenArchive(book);

      expect(_entryText(archive, 'mimetype'), 'application/epub+zip');
    });

    // TC-WRT-5 [Scenario/use-case]: binary content goes through untouched
    // rather than being utf8-encoded like the text branch.
    test('TC-WRT-5 [Scenario]: image bytes are copied verbatim', () async {
      final EpubBook book = await const EpubReader().readBook(_seedArchive());

      final Archive archive = _writtenArchive(book);

      expect(
        archive.files
            .firstWhere((ArchiveFile f) => f.name == 'OEBPS/cover.png')
            .content,
        seedPngBytes(),
      );
    });

    // TC-WRT-10 [Equivalence partitioning]: a spine with no `toc`, which
    // EPUB3 allows, is written with the attribute left off. The written OPF
    // parses back to the same package with the toc still null and the guide
    // still absent — every part but the manifest, whose nav declaration is a
    // named loss (TC-PKW-3). That loss is also why the whole book cannot make
    // the trip: without `properties="nav"` the re-read finds no table of
    // contents.
    test(
        'TC-WRT-10 [Equivalence]: a spine with no toc is written without the '
        'attribute', () async {
      final EpubBook original =
          await const EpubReader().readBook(_epub3ArchiveWithoutTocOrGuide());
      final EpubPackage package = original.schema.package;
      expect(package.spine.tableOfContents, isNull);
      expect(package.guide, isNull);

      final Archive archive = _writtenArchive(original);
      final EpubPackage reread =
          await const PackageReader().readPackage(archive, 'OEBPS/content.opf');

      expect(_entryText(archive, 'OEBPS/content.opf'),
          contains('<spine><itemref idref="ch1" linear="yes"/></spine>'));
      expect(reread.version, EpubVersion.epub3);
      expect(reread.metadata, package.metadata);
      expect(reread.spine.tableOfContents, isNull);
      expect(reread.guide, isNull);
      await expectLater(_roundTrip(original),
          throwsA(isA<EpubUnresolvedReferenceException>()));
    });

    // TC-WRT-11 [Error guessing]: `EpubContentFile` is open to subclassing,
    // and a content file that is neither text nor bytes has no serialisation.
    // The writer refuses it by name instead of writing an empty entry.
    test(
        'TC-WRT-11 [Error guessing]: a content file that is neither text nor '
        'bytes is refused', () async {
      final EpubBook book = _withAllFiles(
        await const EpubReader().readBook(_seedArchive()),
        <String, EpubContentFile>{
          'NGE-SEED-unknown.bin': const _UnknownContentFile(),
        },
      );

      expect(
          () => const EpubWriter().writeBook(book),
          throwsA(isA<ArgumentError>()
              .having((ArgumentError e) => e.name, 'name', 'book.content')
              .having((ArgumentError e) => e.invalidValue, 'invalidValue',
                  _UnknownContentFile)));
    });
  });

  group('EpubWriter.writeBook known losses', () {
    // TC-WRT-6 [Error guessing]: the container the writer emits names
    // `OEBPS/content.opf` as a constant, while the OPF itself is written under
    // the book's own `contentDirectoryPath`. A book whose OPF sat anywhere
    // else comes back pointing at an entry that does not exist.
    test(
        'TC-WRT-6 [Error guessing]: a non-OEBPS content directory writes a '
        'container that points at nothing', () async {
      final EpubBook book = await const EpubReader().readBook(buildEpubArchive(
        opfPath: 'content.opf',
        textEntries: <String, String>{
          'content.opf': _opf(),
          'toc.ncx': _ncx,
          'chapter1.xhtml': seedXhtml('NGE-SEED Chapter One'),
          'style.css': 'p { color: #123456; } /* NGE-SEED */',
        },
        binaryEntries: <String, List<int>>{'cover.png': seedPngBytes()},
      ));

      final Archive archive = _writtenArchive(book);

      expect(_entryText(archive, 'META-INF/container.xml'),
          contains('full-path="OEBPS/content.opf"'));
      expect(_entryNames(archive), isNot(contains('OEBPS/content.opf')));
      await expectLater(_roundTrip(book), throwsA(isA<EpubException>()));
    });

    // TC-WRT-8 [Equivalence partitioning]: spine linearity inverts on EVERY
    // trip, for all three ways the attribute can arrive.
    // `PackageReader.readSpine` maps an absent `linear` AND `linear="no"` to
    // `isLinear = true`, leaving `linear="yes"` as the only false; the writer
    // maps `isLinear == true` back to `linear="yes"`. The pair has no fixed
    // point, so a book cannot be written and read without the flag flipping.
    void linearityInverts(String itemRef, String spelling, bool isLinear) {
      test('TC-WRT-8 [Equivalence]: spine linear=$spelling inverts', () async {
        final EpubBook original = await const EpubReader()
            .readBook(_seedArchive(spineItemRef: itemRef));
        expect(original.schema.package.spine.items.single.isLinear, isLinear);

        final EpubBook reread = await _roundTrip(original);

        expect(reread.schema.package.spine.items.single.isLinear, !isLinear);
      });
    }

    linearityInverts('<itemref idref="ch1"/>', 'absent', true);
    linearityInverts('<itemref idref="ch1" linear="no"/>', 'no', true);
    linearityInverts('<itemref idref="ch1" linear="yes"/>', 'yes', false);
  });
}
