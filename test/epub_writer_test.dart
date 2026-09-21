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
import 'package:test/test.dart';

import 'support/epub_fixture.dart';

/// The OPF directory `EpubWriter` is hard-wired to (see TC-WRT-6); every
/// round-trip fixture has to use it or the rewritten container points at
/// nothing.
const String _contentDir = 'OEBPS';

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
/// [spineItemRef] and [guide] are injected so a test can vary the one part it
/// is about without restating the other forty lines.
String _opf({
  String spineItemRef = '<itemref idref="ch1"/>',
  String guide = '<guide>'
      '<reference type="toc" title="NGE-SEED Contents" href="chapter1.xhtml"/>'
      '</guide>',
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
    '</manifest>'
    '<spine toc="ncx">$spineItemRef</spine>'
    '$guide'
    '</package>';

Uint8List _seedArchive({
  String spineItemRef = '<itemref idref="ch1"/>',
  String guide = '<guide>'
      '<reference type="toc" title="NGE-SEED Contents" href="chapter1.xhtml"/>'
      '</guide>',
}) =>
    buildEpubArchive(
      opfPath: '$_contentDir/content.opf',
      textEntries: <String, String>{
        '$_contentDir/content.opf':
            _opf(spineItemRef: spineItemRef, guide: guide),
        '$_contentDir/toc.ncx': _ncx,
        '$_contentDir/chapter1.xhtml': seedXhtml('NGE-SEED Chapter One'),
        '$_contentDir/style.css': 'p { color: #123456; } /* NGE-SEED */',
      },
      binaryEntries: <String, List<int>>{
        '$_contentDir/cover.png': seedPngBytes(),
      },
    );

Future<EpubBook> _roundTrip(EpubBook book) async =>
    EpubReader.readBook(EpubWriter.writeBook(book)!);

Archive _writtenArchive(EpubBook book) =>
    ZipDecoder().decodeBytes(EpubWriter.writeBook(book)!);

String _entryText(Archive archive, String name) => convert.utf8.decode(
    archive.files.firstWhere((ArchiveFile f) => f.name == name).content
        as List<int>);

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
      final EpubBook original = await EpubReader.readBook(_seedArchive());

      final EpubBook reread = await _roundTrip(original);
      for (final EpubSpineItemRef item
          in reread.Schema!.Package!.Spine!.Items!) {
        item.IsLinear = !item.IsLinear!;
      }

      expect(reread, original);
    });

    // TC-WRT-2 [Scenario/use-case]: the same trip, asserted part by part, so a
    // regression names the part it broke instead of only saying "not equal".
    test('TC-WRT-2 [Scenario]: each part of the book survives independently',
        () async {
      final EpubBook original = await EpubReader.readBook(_seedArchive());

      final EpubBook reread = await _roundTrip(original);

      expect(reread.Title, original.Title);
      expect(reread.Author, original.Author);
      expect(reread.AuthorList, original.AuthorList);
      expect(reread.Schema!.ContentDirectoryPath,
          original.Schema!.ContentDirectoryPath);
      expect(
          reread.Schema!.Package!.Metadata, original.Schema!.Package!.Metadata);
      expect(
          reread.Schema!.Package!.Manifest, original.Schema!.Package!.Manifest);
      expect(reread.Schema!.Package!.Guide, original.Schema!.Package!.Guide);
      expect(reread.Schema!.Navigation, original.Schema!.Navigation);
      expect(reread.Content, original.Content);
      expect(reread.Chapters, original.Chapters);
      expect(reread.CoverImage!.getBytes(), original.CoverImage!.getBytes());
    });

    // TC-WRT-9 [Scenario/use-case]: the parts of the spine that DO survive —
    // the `toc` idref, the reading direction and the item order — separated
    // from the linearity flag that does not.
    test('TC-WRT-9 [Scenario]: the spine keeps its toc, direction and order',
        () async {
      final EpubBook original = await EpubReader.readBook(_seedArchive(
          spineItemRef: '<itemref idref="ch1"/><itemref idref="css"/>'));

      final EpubSpine spine =
          (await _roundTrip(original)).Schema!.Package!.Spine!;

      expect(spine.TableOfContents, 'ncx');
      expect(spine.ltr, isTrue);
      expect(spine.Items!.map((EpubSpineItemRef i) => i.IdRef),
          <String>['ch1', 'css']);
    });
  });

  group('EpubWriter.writeBook archive layout', () {
    // TC-WRT-3 [Scenario/use-case]: the four kinds of entry the writer emits.
    test('TC-WRT-3 [Scenario]: emits mimetype, container, content and the OPF',
        () async {
      final EpubBook book = await EpubReader.readBook(_seedArchive());

      final Archive archive = _writtenArchive(book);

      expect(
        archive.files.map((ArchiveFile f) => f.name),
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
      final EpubBook book = await EpubReader.readBook(_seedArchive());

      final Archive archive = _writtenArchive(book);

      expect(_entryText(archive, 'mimetype'), 'application/epub+zip');
    });

    // TC-WRT-5 [Scenario/use-case]: binary content goes through untouched
    // rather than being utf8-encoded like the text branch.
    test('TC-WRT-5 [Scenario]: image bytes are copied verbatim', () async {
      final EpubBook book = await EpubReader.readBook(_seedArchive());

      final Archive archive = _writtenArchive(book);

      expect(
        archive.files
            .firstWhere((ArchiveFile f) => f.name == 'OEBPS/cover.png')
            .content,
        seedPngBytes(),
      );
    });
  });

  group('EpubWriter.writeBook known losses', () {
    // TC-WRT-6 [Error guessing]: the container the writer emits names
    // `OEBPS/content.opf` as a constant, while the OPF itself is written under
    // the book's own `ContentDirectoryPath`. A book whose OPF sat anywhere
    // else comes back pointing at an entry that does not exist.
    test(
        'TC-WRT-6 [Error guessing]: a non-OEBPS content directory writes a '
        'container that points at nothing', () async {
      final EpubBook book = await EpubReader.readBook(buildEpubArchive(
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
      expect(archive.files.map((ArchiveFile f) => f.name),
          isNot(contains('OEBPS/content.opf')));
      await expectLater(_roundTrip(book), throwsA(isA<EpubException>()));
    });

    // TC-WRT-7 [Error guessing]: `EpubGuideWriter` dereferences the guide
    // unconditionally, but `PackageReader` leaves it null when the OPF has no
    // `<guide>` — which is the norm in EPUB 3. Writing such a book throws.
    test('TC-WRT-7 [Error guessing]: a book with no guide cannot be written',
        () async {
      final EpubBook book = await EpubReader.readBook(_seedArchive(guide: ''));

      expect(book.Schema!.Package!.Guide, isNull);
      expect(() => EpubWriter.writeBook(book), throwsA(isA<TypeError>()));
    });

    // TC-WRT-8 [Equivalence partitioning]: spine linearity inverts on EVERY
    // trip, for all three ways the attribute can arrive.
    // `PackageReader.readSpine` maps an absent `linear` AND `linear="no"` to
    // `IsLinear = true`, leaving `linear="yes"` as the only false; the writer
    // maps `IsLinear == true` back to `linear="yes"`. The pair has no fixed
    // point, so a book cannot be written and read without the flag flipping.
    for (final List<Object> row in <List<Object>>[
      <Object>['<itemref idref="ch1"/>', 'absent', true],
      <Object>['<itemref idref="ch1" linear="no"/>', 'no', true],
      <Object>['<itemref idref="ch1" linear="yes"/>', 'yes', false],
    ]) {
      test('TC-WRT-8 [Equivalence]: spine linear=${row[1]} inverts', () async {
        final EpubBook original = await EpubReader.readBook(
            _seedArchive(spineItemRef: row[0] as String));
        expect(original.Schema!.Package!.Spine!.Items!.single.IsLinear, row[2]);

        final EpubBook reread = await _roundTrip(original);

        expect(reread.Schema!.Package!.Spine!.Items!.single.IsLinear,
            !(row[2] as bool));
      });
    }
  });
}
