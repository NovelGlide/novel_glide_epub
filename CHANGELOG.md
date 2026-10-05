# Changelog

## 0.3.0

**Breaking: equality is decided by `package:equatable`, and `quiver` is no
longer a dependency.** Every entity, ref entity and schema class that
compared itself by hand now extends `Equatable` and lists the fields it
compares in `props`; the hand-written `operator ==` and `hashCode` are gone.
The fields compared are the same as before, except for
`EpubMetadataMeta.attributes` (below).
Lists and maps are still compared by element. `EpubBook` still compares its
cover by the bytes it decodes to, and `EpubBookRef` and `EpubContentFileRef`
still leave out the archive they read from.

- **The runtime type is compared.** Two objects of different classes are
  never equal, whatever their fields hold.

  ```dart
  final EpubTextContentFileRef text = book.content.html['a.xhtml']!;
  final EpubByteContentFileRef bytes = EpubByteContentFileRef(
    epubArchive: archive,
    contentDirectoryPath: 'OEBPS',
    fileName: text.fileName,
    contentType: text.contentType,
    contentMimeType: text.contentMimeType,
  );

  // Before
  text == bytes; // true, and both hashed alike
  // After
  text == bytes; // false
  ```

  The same goes for a subclass of `EpubContentFile` with no fields of its
  own. Before, it inherited a `==` that accepted any `EpubContentFile` with
  matching base fields, so it equalled a text file while the text file did
  not equal it. Now neither equals the other.
- **`EpubMetadataMeta` compares `attributes`.** Two metas that differ only
  in their attribute map are now unequal; before, the map was left out of
  `==` and `hashCode`. The map is compared by entry, so the order its
  entries were added in doesn't matter.

  ```dart
  const EpubMetadataMeta a = EpubMetadataMeta(
      content: 'x', attributes: <String, String>{'lang': 'en'});
  const EpubMetadataMeta b = EpubMetadataMeta(
      content: 'x', attributes: <String, String>{'lang': 'ja'});

  // Before
  a == b; // true
  // After
  a == b; // false
  ```

- **Every `hashCode` changes.** Equatable hashes the runtime type and the
  `props`, so no class gives the hash code it gave before. Don't persist a
  hash code or compare one across versions.
- **`toString` changes where a class had none of its own.**
  - `EpubBook`, `EpubContent`, `EpubTextContentFile` and
    `EpubByteContentFile` now print a one-line summary, with or without
    assertions, where they printed `Instance of '…'`. None of them prints a
    file's content, its bytes or the cover, so the line stays short however
    big the book is:

    | Class | Prints |
    |---|---|
    | `EpubBook` | `Title: <title>, Chapter count: <n>` |
    | `EpubContent` | `HTML: <n>, CSS: <n>, Images: <n>, Fonts: <n>, All files: <n>` |
    | `EpubTextContentFile` | `File name: <name>, Content type: <type>, MIME type: <mime>, Length: <n> characters` |
    | `EpubByteContentFile` | `File name: <name>, Content type: <type>, MIME type: <mime>, Length: <n> bytes` |

  - Every other converted class without a `toString` of its own takes
    `Equatable`'s. When it stringifies, it prints the class name and the
    fields it compares: for example
    `EpubMetadataDate(2026-09-21, publication)` where it printed
    `Instance of 'EpubMetadataDate'`. Nested fields print the same way, so
    `EpubSchema` prints its package's version, metadata, manifest, spine and
    guide, its navigation and its content directory path, and `EpubBookRef`
    prints its schema plus the name, type and MIME type of every file it
    refers to. None of them prints a file's content.
  - Whether these classes stringify is `EquatableConfig.stringify`, a global
    a consumer can set; none of them overrides `stringify`. Left unset, it
    is true when assertions are enabled, as under `dart test` and in a debug
    build, and false otherwise.
  - When they don't stringify, the output depends on the `equatable` version
    a consumer resolves: 3.x prints `Instance of '…'`, as before, and 2.x
    prints only the class name, such as `EpubMetadataDate`.
  - Classes that already had a `toString`, such as `EpubChapter` and
    `EpubManifestItem`, are unchanged.
- **Every converted class is `@immutable`**, which it inherits from
  `Equatable`. A consumer's subclass of one, such as of `EpubContentFile` or
  `EpubContentFileRef`, gets the analyzer's `must_be_immutable` warning if it
  declares a field that isn't final. Where a consumer enables the
  `prefer_const_literals_to_create_immutables` lint, a non-const literal
  passed to one of these constructors can trigger it.
- **Every converted class has two new public getters**, `props` and
  `stringify`, from `Equatable`.
- **`quiver` is no longer a dependency.** A consumer that used it without
  declaring it has to add it to its own `pubspec.yaml`.

**Breaking: `EpubBookRef.epubArchive()` is removed. Read an entry by its
archive name with `readEntry`, and look up the sizes of the entries the book
keeps in `knownEntrySizes`.** An opened book no longer holds a record for
every entry its ZIP directory lists, so it has no archive of every entry to
hand out.

```dart
// Before
final ArchiveFile? image = ref.epubArchive().findFile('OEBPS/images/bg.png');
final List<int>? bytes = image?.content as List<int>?;
final int? size = ref.epubArchive().findFile('OEBPS/content.opf')?.size;

// After
final Uint8List? bytes = await ref.readEntry('OEBPS/images/bg.png');
final int? size = ref.knownEntrySizes['OEBPS/content.opf'];
```

- `readEntry(String name, {int? maxBytes})` returns the bytes of any entry
  by its full name in the archive, whether the manifest lists it or not,
  and `null` when the archive has no such entry. Each read inflates the
  entry anew, held to the `maxEntryBytes` the book was opened with and,
  when `maxBytes` is given, to the tighter of the two; the inflater stops
  part-way with `EpubArchiveTooLargeException` as soon as the entry passes
  it. A damaged entry throws `EpubCorruptArchiveException`, and one
  compressed with a method an EPUB may not use
  `EpubUnsupportedCompressionException`. A `maxBytes` below zero throws
  `ArgumentError`.
- `knownEntrySizes` maps each entry the book keeps to the uncompressed size
  its header declares: `mimetype`, every `META-INF/` entry, the package
  document, every file the manifest lists that the archive holds, and the
  case variants described below. An entry `readEntry` finds outside them is
  not added. Each access builds a new map; a caller that looks at it
  repeatedly keeps the map.
- Over an `Archive` the caller built, which has no `maxEntryBytes`,
  `readEntry` is held to `maxBytes` alone, checked against the count of
  bytes `ArchiveFile.content` gives before they are copied. It returns a
  copy of the bytes, from a list or from the stream of a file made with
  `ArchiveFile.stream`, and no bytes for a file made with no content. A
  refused read costs nothing only for a file already holding a list, or
  one made with `ArchiveFile.stream`. For a file whose content
  `package:archive` produces when it is asked for, every file a
  `ZipDecoder` decodes, or one made with the plain `ArchiveFile(name, size,
  stream)` constructor, `ArchiveFile.content` inflates or reads the whole
  entry, with no limit, and keeps it, and `maxBytes` refuses it only
  afterwards. A caller reading files it does not trust opens them with
  `EpubReader.openBook` or `openBookFile`, whose reads are stopped part-way.
- `EpubContentFileRef.openContentStream`, and the reads that go through it,
  now read a file a caller made with `ArchiveFile.stream`, as what is left of
  its stream, where they threw `EpubMissingArchiveEntryException`; a file
  made with no content still throws it. `ArchiveFile.content` is turned into
  bytes the same way in both places.
- **Opening holds what grows with `META-INF/` and the manifest, not with the
  ZIP's records.** Opening reads the central directory through the same
  4 KiB window as before and keeps the location of the entries above only;
  every other record is read and dropped. Measured opening a book from a
  file, with more zero-length records its manifest does not list:

  | Extra records | Peak memory growth, before | After | Open time, before | After |
  | ---: | ---: | ---: | ---: | ---: |
  | 4,096 | 3 MiB | 2 MiB | 0.02 s | 0.03 s |
  | 100,000 | 53 MiB | 3 MiB | 0.3 s | 0.8 s |
  | 1,000,000 | 281 MiB | 3 MiB | 3.8 s | 7.7 s |

- Opening still reads every record, in three passes at most: one checking
  each record and keeping the `META-INF/` entries, one finding the package
  document the container names (skipped when it is one of those), and one
  keeping the manifest's files. So opening takes time in proportion to the
  directory, about twice what it did. The checks on every record are
  unchanged: a negative size, or compressed sizes adding up to more than
  the file, fail the book with `EpubCorruptArchiveException` whichever
  record declares them.
- An entry the manifest does not list, such as an image only a stylesheet
  points at, costs one more pass over the directory the first time it is
  read, through `readEntry` or an `EpubContentFileRef`; after that it is
  kept and read directly. A name the archive does not hold is looked for
  again each time it is asked for.
- The table of contents is still looked up regardless of case. Of the
  entries whose names match the package document's or a manifest file's but
  for case, the spelling that comes first in the directory is kept as well
  (its last record, when it has several, as for any name), one for each
  document at most. They are listed in `knownEntrySizes` under the names
  the archive gives them. So the lookup finds the entry it found before,
  except in one arrangement: the table of contents lies inside `META-INF/`
  (as it does when the package document is there), and the directory spells
  it both as `META-INF/…` and in another case (`meta-inf/…`). Opening keeps
  the `META-INF/` spelling first, so the lookup finds it, even where the
  other comes first in the directory.

**Breaking: the package has no built-in limits; each call passes its own.**
How large a file may be, how many entries it may hold, and how much an entry
may inflate to are the caller's decision. The entry points take the
inflation limits as required named parameters, with no default, so every
call site states them:

```dart
// Before
final EpubBookRef ref = await reader.openBook(bytes);
final EpubBook book = await reader.readBookFile(path);

// After
final EpubBookRef ref =
    await reader.openBook(bytes, maxEntryBytes: 256 * 1024 * 1024);
final EpubBook book = await reader.readBookFile(path,
    maxEntryBytes: 256 * 1024 * 1024, maxTotalBytes: 512 * 1024 * 1024);
```

- `openBook(bytes, {required int? maxEntryBytes})` and
  `openBookFile(path, {required int? maxEntryBytes})`: every read of an
  entry through the returned `EpubBookRef` (`readContentAsBytes`,
  `readContentAsText`, `getContentStream`, `openContentStream`,
  `EpubChapterRef.readHtmlContent`, `readCover`, `readCoverBytes`, and
  `readEntry`) inflates it to at most `maxEntryBytes`.
- `readBook(bytes, {required int? maxEntryBytes, required int?
  maxTotalBytes})` and `readBookFile(path, {...})`: each entry held to
  `maxEntryBytes`, and what the entries the one call reads inflate to
  between them, the documents parsed to open the book included, to
  `maxTotalBytes`.
- **`null` sets no limit. Without one, a crafted entry can inflate until
  memory runs out:** a caller reading files it does not trust passes limits.
  A limit below zero throws `ArgumentError`, a mistake in the call rather
  than in the book.
- A read passing a limit is stopped part-way by the one inflater every read
  goes through, and throws `EpubArchiveTooLargeException`, holding no more
  than the limit, whatever size the entry declares.
- Opening a book checks neither the file's size nor its number of entries:
  a file of any size, with any number of entries, opens. What opening holds
  grows with the book's `META-INF/` entries and its manifest, not with the
  number of entries the ZIP has (see above).
- The size an entry declares is never allocated on its word: an entry is
  inflated into a buffer of the size it declares, capped at its limit and at
  what its compressed bytes can inflate to (their own length stored, 1032
  times it deflated), so an honest entry is held once, limit or none.

**Behaviour change: an `EpubBookRef` keeps nothing it reads, and its reads
share no total.** How long a ref is kept, and whether what it reads is
cached, is the caller's decision.

- Every read of an entry through a ref inflates it again and hands the bytes
  to the caller: `readContentAsBytes`, `readContentAsText`,
  `getContentStream`, `openContentStream`, `readCover`, `readCoverBytes`,
  `EpubChapterRef.readHtmlContent`, `readEntry`, and `ArchiveFile.content`
  and `writeContent` on the entry `EpubContentFileRef.getContentFileEntry`
  returns. Nothing in the ref keeps the bytes, so a ref kept for a long time
  does not
  grow, and reading one entry twice inflates it twice, each read getting
  bytes of its own. A caller that reads an entry repeatedly and wants it
  inflated once keeps the bytes itself. An entry changed in the source after
  a read is read as it is then by the next.
- A read through a ref is held to `maxEntryBytes` alone: reads of one ref
  share no running total, so a ref kept long enough never refuses every
  further read.
- `readBook` and `readBookFile` hold what the one call reads to
  `maxTotalBytes`, since the `EpubBook` they return holds it all at once.
  Within the call each entry is inflated and counted once, the chapter text
  read for both the content and the chapters included.

**Decompression guarded where it happens.** An entry is inflated only when
it is read, by one inflater that holds every read to the limits the call
passed. Opening a book inflates nothing but the documents it parses; what a
read costs in memory is the entry it reads.

The sizes the entries declare are not held against the limits: they are
the archive's own claim, which a decompression bomb lies in. A book with an
entry honestly declaring 300 MiB opens, and under a 256 MiB limit that
entry is refused if it is read.

- A read past a limit throws **`EpubArchiveTooLargeException`**, a new
  member of the sealed `EpubException` family. This is **breaking** for an
  exhaustive `switch` on `EpubException`, which now has to handle it and
  the two members below.
- There is no separate check to call: every read of an entry, by any entry
  point, goes through the same inflater, held to the limits its book was
  opened or read with. The package has no validation or import API; what a
  caller does with the bytes it reads, such as handing them to another
  decoder, is the caller's to guard.
- **A damaged ZIP container now throws the new
  `EpubCorruptArchiveException`**, a member of the same family:
  - bytes that are not a ZIP at all, or whose end-of-central-directory
    record is cut short, which threw `ArchiveException` or a `RangeError`;
  - any ZIP structure that reaches past the end of the file or has a
    negative length: a central directory, zip64 record, directory record or
    local header placed or sized past the end, an entry's compressed data or
    its data descriptor (bit 3, as streaming writers set) running off it.
    These threw a `RangeError`, or were read short without an error.
    `package:archive` reads the container only through a stream that checks
    every read against its end;
  - a container `package:archive` cannot parse (a broken local header, say),
    which threw `ArchiveException`;
  - an entry whose deflate stream zlib rejects, which threw
    `FormatException`;
  - a central directory whose entries declare more compressed bytes between
    them than the file holds, or any size below zero (`package:archive`
    reads a zip64 size as a signed value), checked when the book is opened,
    which is new: entries that overlap, sharing one stream, would have it
    inflated once per entry by a book read whole. A negative size, which no
    entry can really have, is refused rather than added, so no entry can pull
    the total back down.

  `TypeError` and `StateError` still escape unconverted: they mean a defect
  in this package or `package:archive`, not a damaged book. So does a
  `RangeError` from the two places `package:archive` copies bytes into a
  stream of its own, the extra field of any central-directory record and
  the extra field of a local header whose entry has its encryption flag
  set, when one is damaged so that parsing it reads past its own end: it
  cannot be told apart from a defect, so it is not caught.
- **New: `openBookFile(path, ...)` and `readBookFile(path, ...)`.** They
  read the file a chunk at a time; it is never loaded whole, whatever its
  size. They bring in `dart:io`, so the package no longer compiles for the
  web.
- **No new obligation to close anything.** An `EpubBookRef` from
  `openBookFile` holds the path, not an open file: each later read opens the
  file, reads the one entry through the same limit, and closes it. What the
  caller sees if the file changes in between: a file removed, or no longer
  readable, fails that read with `FileSystemException`; one cut short so the
  entry is no longer in it, or whose entry no longer inflates, with
  `EpubCorruptArchiveException`; one whose entry now inflates past the
  limit, with `EpubArchiveTooLargeException`. Bytes changed in place within
  the limit are read as they are then: nothing records an entry's content when
  the book is opened, so nothing checks it against that.
- The `archive` dependency now requires `^3.6.1`: the decode uses its public
  `ZipFileHeader`, `ZipFile` and `InputStream` API as of that version.
- **Opening a book reads its directory and the documents it parses.** The
  central directory is read here, record by record, rather than by
  `package:archive`'s `ZipDirectory.read`, every record until the
  directory's bytes run out, whatever count the end record claims. Their
  declared sizes are checked
  against the file, as above, and of the entries only the container,
  package and navigation documents are read. No other entry is touched,
  neither its local header nor its data: opening costs at most three passes
  over the directory's records (see above), whatever the entries hold. `ZipDirectory.read` parsed every entry's local header as well,
  keeping a copy of each one's extra field.
- **An entry is inflated each time it is read**; within one `readBook`
  call, each entry is inflated once. The inflater counts the
  bytes it really produces and abandons the entry as soon as they cross
  `maxEntryBytes` or, in `readBook`, what `maxTotalBytes` has left. A header
  that under-declares its size gets no further than the limit; within the
  limits an entry that inflates past its declared size is read, since
  writers misstate it in good faith (`package:archive`'s `ArchiveFile.string`
  declares a text's UTF-16 length). An entry is inflated into a buffer of
  the size it declares, capped at what the limits leave and at what its
  compressed bytes can inflate to, the one use made of that size: an honest
  entry is held once, and one that inflates past its declared size keeps its
  chunks and is joined once at the end. What a read costs is the entry, and one read refused part-way the
  limit it crossed.
- **`readBook` and `readBookFile` read the book through the same reads.**
  Each entry the `EpubBook` holds is inflated once, by the same inflater
  under the limits the call passed; what they cost is the `EpubBook` they
  return.
- **Behaviour changes that come with inflating on read:**
  - **A damaged, too large or unsupported entry fails when it is read, not
    when the book is opened**, a damaged local header included. A book
    whose bad entry nothing reads, a stray `__MACOSX/` file say, opens and
    reads; `readBook` fails for one the book holds. Before, an entry with a
    broken local header failed the book when it was opened, one with
    damaged data when it was read, and a decompression bomb was not refused
    at all.
  - `openBook` holds the bytes it was given, and reads each content file
    from them when asked, inflating a content file each time it is read.
  - **Reading a content file holds it once.**
    `EpubContentFileRef.openContentStream` and `getContentStream` return
    the bytes the read inflated, a `Uint8List` (they returned `List<int>`),
    as they are; each read returns bytes of its own.
    `readContentAsBytes` and `readContentAsText` read through them, and
    `BookCoverReader` decodes the cover from them. Before, every read copied
    the entry into a growable `List<int>`, eight bytes to each byte of it,
    then copied that again: a 200 MiB audio file read as bytes cost over
    2 GiB at its peak, and now costs the file. The narrower return type is source-compatible for callers; a subclass that
    overrides either method returning `List<int>` no longer compiles.
  - DEFLATE is still inflated by `dart:io`'s zlib, now through
    `RawZLibFilter`, fed a chunk at a time so the limits stop it part-way. An
    invalid stream fails with `EpubCorruptArchiveException`; one cut short
    still yields what it holds, without an error, as before.
  - `EpubArchiveTooLargeException` messages give sizes and limits, never an
    entry's file name, which can carry the book's title.
  - The entries `EpubContentFileRef.getContentFileEntry` returns carry their
    name, their content, inflated each time it is asked for, and the `size`
    their header declares, as before. They no longer carry the ZIP's CRC,
    file mode, modification time, or directory and symlink flags.
  - Only STORE and DEFLATE entries are read, the two methods the EPUB
    container format allows. Reading an entry in any other method, BZIP2
    included, throws the new **`EpubUnsupportedCompressionException`**;
    before, BZIP2 was read and other methods threw `ArchiveException`. The
    ZIP encryption flag is ignored; the EPUB container format forbids ZIP
    encryption. An entry with the flag set but its bytes in the clear now
    reads, where it used to throw `FormatException`.
  - The end record is searched for from the last position a whole one
    fits. A valid ZIP whose comment ends with the end-record signature now
    opens, where `ZipDirectory.read` matched that signature first and threw
    a `RangeError`.

**Breaking.**

- **Nullability follows the EPUB spec.** Every class under `entities/`,
  `ref_entities/` and `schema/` (OPF, NCX and nav) declares a field non-null
  when the spec requires the element or attribute, and nullable only when the
  spec makes it optional. The nullable fields that remain:
  - `EpubBook.coverImage`; `EpubChapter.anchor`, `EpubChapterRef.anchor`.
  - `EpubPackage.guide`, `EpubGuideReference.title`,
    `EpubSpine.tableOfContents` (required by EPUB 2 only).
  - `EpubManifestItem`: `mediaOverlay`, `requiredNamespace`,
    `requiredModules`, `fallback`, `fallbackStyle`, `properties`.
  - `fileAs` and `role` on `EpubMetadataCreator` and
    `EpubMetadataContributor`;
    `EpubMetadataDate.event`; `EpubMetadataIdentifier.id` and `scheme`;
    `EpubMetadataMeta.name`, `id`, `refines`, `property`, `scheme`.
  - `EpubNavigation.pageList`; `EpubNavigationContent.id` and `source`;
    `EpubNavigationHeadMeta.scheme`; `id` and `className` on
    `EpubNavigationList`; `className` on `EpubNavigationPoint`;
    `className` and `value` on `EpubNavigationTarget` and
    `EpubNavigationPageTarget`.

  Every list is non-null, and empty when the book has none of that element.
- **A required value a real book leaves out reads as empty; the book still
  opens.** No refusal was added. Each fallback is documented on its field:
  - `title` is `''` when the package has no `dc:title`.
  - `EpubMetadataMeta.content` is `''` for an EPUB 2 `<meta>` without
    `content`.
  - `playOrder` is `''` on a navPoint, navTarget or pageTarget without one;
    a pageTarget's `id` is `''` when absent.
  - A pageTarget's `type` is `EpubNavigationPageTargetType.undefined` when
    absent or unrecognised (it was null). A literal `type="undefined"` is
    still refused.
  - A navTarget or pageTarget with no `<content>` gets an
    `EpubNavigationContent` with no source.
  - An EPUB 3 book's navigation has a `head` with no metadata, no
    `navLists` and no `docAuthors`, and its points have `id` and
    `playOrder` `''`.
  - `EpubNavigationContent.source` is null for an EPUB 3 nav entry that is
    a heading (`<span>`, or `<a>` without `href`).
- **Every entity, ref and schema object is immutable** and built once,
  through a `const` constructor with named parameters. Fields are `final`;
  the `X()..field = value` style no longer compiles. The readers collect each
  value first and construct the object at the end, and every list and map
  they hand in is unmodifiable (a byte content's `Uint8List` excepted), so an
  entity's hash code cannot change after it is built.
- **`EpubMetadata.description` is now `descriptions`**, a `List<String>` of
  every `dc:description` in document order. The element may repeat (one per
  language, say); the old field kept only the last.
- **`author` is removed** from `EpubBookRef` and `EpubBook`. `authorList` is a
  non-null `List<String>`, empty when the book names no creator; joining the
  names for display is the caller's decision.
- **The content maps are keyed by decoded file name.** `html`, `css`,
  `images`, `fonts` and `allFiles` on `EpubContentRef` and `EpubContent` are
  keyed by `ZipPathResolver.decodeHref` of the manifest href (the same string
  as the file's `fileName`), not by the href as the manifest wrote it. Decode
  a manifest or navigation href the same way before looking it up;
  `ZipPathResolver` is now exported for that. `ChapterReader` makes one
  decoded lookup, so a navigation that writes raw a name the manifest escapes
  now finds its chapter. Two manifest items whose hrefs decode to one name
  are one entry; the later wins.
  The chapter names follow: `contentFileName` on `EpubChapterRef` and
  `EpubChapter`, and `EpubChapterRef.otherContentFileNames`, are the decoded
  name too. Before, a book that escaped a name the same way in the manifest
  and the navigation got the escaped spelling. Compare them with
  `ZipPathResolver().decodeHref(manifestItem.href)`, not the raw href.
- Signatures that changed with the above:
  - `EpubContentFileRef` and its two subclasses take the `Archive` and the
    content directory path instead of the `EpubBookRef`; the `epubBookRef`
    field is gone.
  - `ContentReader.parseContentMap(Archive, String contentDirectoryPath,
    EpubManifest)` replaces `parseContentMap(EpubBookRef)`.
  - `PackageReader.readMetadata` takes a non-null `EpubVersion`.
  - `EpubNavigationWriter.writeNavigationPoint` takes the point's source as
    a third argument.
- An OPF with no `<metadata>`, `<manifest>` or `<spine>` is refused with
  `EpubMissingElementException`. It escaped as a raw `StateError` before,
  which the `EpubException` contract counts as a parser defect.

**Other changes from the same rework:**

- A `<navList>` with `<navLabel>` or `<navTarget>` children is read. It
  crashed on a null list before, which is why the `navigationTargets` branch
  was the one line no test reached.
- `EpubWriter` writes a book with no `<guide>`, a spine with no `toc`, and
  a guide reference with no `title`, by leaving the element or attribute out;
  all three threw before. An EPUB 2 `<meta>` is always written with its
  `content`, so one read without it is written back with `content=""`. The
  writer throws `ArgumentError` for a content file that is neither text nor
  bytes. `EpubNavigationWriter` leaves out a nav entry with no source, which
  NCX cannot express.
- `EpubMetadataMeta.attributes` holds every attribute of an EPUB 2 `<meta>`
  too, not only of an EPUB 3 one.
- `EpubReader.readBook` fills `EpubChapter.otherContentFileNames` for a
  chapter split into `_split_` files; it was always empty.
- `ZipPathResolver.combine` takes non-null `String` arguments; a null file
  name used to compile and then throw.

**Fixed: books whose files have non-ASCII names could not be opened.** There
were two defects, and the first one fired before the second could:

- Every href was decoded with `Uri.decodeFull`, which throws on a raw
  non-ASCII character. Most CJK books write their hrefs unescaped, so they
  failed while the chapter list was being built. Hrefs are now decoded by
  `ZipPathResolver.decodeHref`:
  - `%XX` escapes are decoded; every other character is kept as written.
  - A `%` that does not start an escape (`100%.xhtml`) is kept literally.
  - Escapes that decode to bytes that are not UTF-8 leave the href
    unchanged.
- `ZipPathResolver.combine` resolved `.` and `..` with `Uri.normalizePath`,
  which percent-encodes non-ASCII characters. ZIP entry names are raw UTF-8,
  so every lookup of such a file missed. It now resolves the segments as
  plain strings.

The two were the "file not found in archive" and chapter-list failures that
NovelGlide 1.2.8 and 1.3.0 report for these books.

Related changes that came with the fix:

- The NCX and EPUB3 nav documents are now found when their manifest href is
  escaped. Their href used to reach `combine` still undecoded.
- A chapter is found whichever way the manifest and the navigation spell
  its href, escaped or raw; see the decoded content-map keys under
  **Breaking** above.
- `combine` reads `\` as `/`, as it did before.
- A `..` with nothing left to climb is now dropped. Before, it was kept as a
  literal `..` segment.
- `EpubWriter` now names archive entries by their decoded file name, not by
  the manifest's escaped href.

## 0.2.0

**Breaking.**

- Every PascalCase public member is now lowerCamelCase, and every
  SCREAMING_CASE enum value is now lowerCamelCase. These were the findings of
  two lint rules (`non_constant_identifier_names`, 143;
  `constant_identifier_names`, 24) that `analysis_options.yaml` had been
  silencing since the extraction; both are now enforced. A representative
  mapping: `EpubBook.Title` → `title`, `EpubSchema.Package` → `package`,
  `EpubContentFile.ContentType` → `contentType`,
  `EpubContentType.XHTML_1_1` → `xhtml11`, `EpubContentType.IMAGE_GIF` →
  `imageGif`, `EpubVersion.Epub2` → `epub2`. The one non-mechanical rename
  is `Class` on `EpubNavigationTarget`, `EpubNavigationPageTarget`,
  `EpubNavigationList` and `EpubNavigationPoint`, which became `className`
  — `class` is a reserved word in Dart.
- `EpubReader` and `EpubWriter` are instance APIs:
  `EpubReader.readBook(bytes)` becomes `const EpubReader().readBook(bytes)`,
  `EpubReader.openBook` likewise, and `EpubWriter.writeBook(book)` becomes
  `const EpubWriter().writeBook(book)`.

**Other changes since 0.1.0:**

- Lint is clean with nothing silenced: `dart run dart_lints` reports 0
  issues, including infos, and the package carries no `errors: ignore`
  entries and no `// ignore` comments.
- The ten call sites still using `XmlNode`'s deprecated `text` getter now use
  `innerText`. The deprecated getter is itself defined as `innerText`, so the
  change is behaviour-preserving at every site.
- The internal `ZipPathResolver.combine` is fully typed and returns a
  non-nullable `String`. A null `fileName` still throws the same `TypeError`;
  the percent-encoding fix it is still due for stays out of scope.
- The test suite grew from 21% line coverage to 492 tests and 1535/1536 lines
  (`a30cfd5`, `0fae2de`, `1219194`, `7f731c3`, `c1e98c4`, `e919726`).
  Mutation testing holds every file at the 80% bar except
  `epub_chapter_ref.dart`, last measured at 75%: 2 of its 8 mutants are
  equivalent (`6d30956`).
- Lint alignment with the NovelGlide app: the app's stock-lint selection is
  now this package's own (`de132eb`, `71f320f`, `6d30956`).
- `ContentReader.parseContentMap` no longer re-assigns the five bucket maps
  that `EpubContentRef`'s own constructor already initialises. That dead
  code was the one thing keeping `content_reader.dart` below the coverage
  bar (`eba69ae`).
- The whole package is `dart format`ted; CI's format check had failed on the last
  three pushes.

## 0.1.0

Extracted from the NovelGlide app, where this parser had been vendored at
`packages/epubx` since 2025. Renamed to `novel_glide_epub`; no behaviour
change.

The extraction exists because the vendored copy sat outside every quality gate
the app has — its lint skipped `packages/`, and both the coverage and mutation
tools only look at the app's own `lib/`. A parser that reads user-supplied
files had no lint, no coverage and no test suite of its own.

Carried over from the vendored copy:

- Nav base-path resolution: a relative `href` in an EPUB 3 nav document keeps
  its first path segment, so a book whose OPF sits at the ZIP root is no longer
  reported as corrupt.

## Before 0.1.0

See [`epubx`](https://github.com/rbcprolabs/epubx.dart), the upstream this is
forked from.
