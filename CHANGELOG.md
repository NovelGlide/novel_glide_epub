# Changelog

## Unreleased

**Archive size limits.** Every entry point now refuses a ZIP container past
fixed limits. Opening a book validates the whole container against them in
one pass that keeps nothing; after that, what one read can cost in memory is
the entry it reads, and what validation can cost in CPU is inflating the
limits' worth of data.

| Limit | Value |
|---|---|
| Compressed input (the file, or the bytes passed in) | 512 MiB |
| Entries in the archive | 4096 |
| Bytes one entry inflates to | 256 MiB |
| Bytes all entries inflate to | 512 MiB |

- A breach throws **`EpubArchiveTooLargeException`**, a new member of the
  sealed `EpubException` family. This is **breaking** for an exhaustive
  `switch` on `EpubException`, which now has to handle it and the two
  members below.
- **A damaged ZIP container now throws the new
  `EpubCorruptArchiveException`**, a member of the same family:
  - bytes that are not a ZIP at all, or whose end-of-central-directory
    record is cut short, which threw `ArchiveException` or a `RangeError`;
  - any ZIP structure that reaches past the end of the file or has a
    negative length: a central directory, zip64 record, directory record or
    local header placed or sized past the end,
    an entry's compressed data or its data descriptor (bit 3, as streaming
    writers set) running off it. These threw a `RangeError`, or were read
    short without an error. `package:archive` reads the container only
    through a stream that checks every read against its end;
  - a container `package:archive` cannot parse (a broken local header, say),
    which threw `ArchiveException`;
  - an entry whose deflate stream zlib rejects, which threw
    `FormatException`;
  - entries given more compressed bytes between them than the file holds,
    which is new: entries that overlap, sharing one stream, would have it
    inflated once per entry. The bytes counted are the ones each entry is
    really given, not the sizes its header claims.

  `TypeError` and `StateError` still escape unconverted: they mean a defect
  in this package or `package:archive`, not a damaged book. So does a
  `RangeError` from the two places `package:archive` copies bytes into a
  stream of its own, the extra field of any central-directory record and
  the extra field of a local header whose entry has its encryption flag
  set, when one is damaged so that parsing it reads past its own end: it
  cannot be told apart from a defect, so it is not caught.
- The limits are private constants. There is nothing to configure and no
  separate check to call: `openBook`, `readBook` and the two new entry points
  all apply them.
- **New: `openBookFile(String path)` and `readBookFile(String path)`.** They
  check the file's size before opening it, so a file past the compressed
  limit is refused without being read, then read the file a 64 KiB chunk at
  a time; it is never loaded whole. They bring in `dart:io`, so the package no
  longer compiles for the web.
- **No new obligation to close anything.** An `EpubBookRef` from
  `openBookFile` holds the path, not an open file: each later read opens the
  file, reads the one entry, and closes it. A file removed by then fails that
  read with `FileSystemException`.
- The `archive` dependency now requires `^3.6.1`: the decode uses its public
  `ZipFileHeader`, `readLocalFileHeader` and `InputStream` API as of that
  version.
- **Opening a book validates the whole container, and keeps nothing.** The
  central directory is read here, record by record, rather than by
  `package:archive`'s `ZipDirectory.read`, so the entries are counted as
  they are read, whatever count the end record claims, and the one past the
  limit is refused before it is built. Their declared sizes are checked
  before anything is inflated. Then every entry is inflated once, counting
  the bytes it really produces, and abandoned when they cross the per-entry
  limit or what the total limit has left. A header that under-declares its
  size gets no further than the limit; within the limits an entry that
  inflates past its declared size still opens, since writers misstate it in
  good faith (`package:archive`'s `ArchiveFile.string` declares a text's
  UTF-16 length). This validation discards what it inflates: its memory is a
  64 KiB chunk of input and one of output, whatever the book's size. It is
  part of opening; there is no separate check to call and no way to skip it.
- **`openBook` and `openBookFile` inflate an entry again when it is read,
  and only then.** An entry nothing reads is never held. A read is held to
  exactly the bytes the entry inflated to when the book was opened, so an
  entry whose bytes changed since (a file rewritten on disk, a list the
  caller changed) is refused: with `EpubCorruptArchiveException` if it
  inflates to fewer bytes, or stopped at that size with
  `EpubArchiveTooLargeException` if more. What a read costs is the entry it
  reads, held once; `ArchiveFile` keeps it for as long as the `EpubBookRef`
  lives, as `package:archive` always did. So every entry read after opening
  is inflated twice, once to validate and once to read; that includes the
  container document, package document and navigation document `openBook`
  itself parses.
- **`readBook` and `readBookFile` inflate each entry once.** They need every
  entry, so validating the container and keeping its content are the same
  pass: the same inflater, the same limits, with the output kept. What they
  cost is the `EpubBook` they return, plus, for a moment, a second copy of
  the entry being inflated.
- **Behaviour changes that come with validating at open:**
  - `openBook` holds the bytes it was given, and reads each content file
    from them when asked; it no longer holds any inflated entry it was not
    asked for. A content file used to be inflated on first read and kept,
    and still is.
  - **Reading a content file holds it once.**
    `EpubContentFileRef.openContentStream` and `getContentStream` return the
    bytes the archive entry holds, a `Uint8List` (they returned
    `List<int>`), without copying them; `readContentAsBytes` and
    `readContentAsText` read through them, and `BookCoverReader` decodes
    the cover from them. Before, every read copied the entry into a growable
    `List<int>`, eight bytes to each byte of it, then copied that again: a
    200 MiB audio file read as bytes cost over 2 GiB at its peak, and now
    costs the file. The bytes returned are shared with every other read of
    the same entry, so a caller that changes them copies them first. The
    narrower return type is source-compatible for callers; a subclass that
    overrides either method returning `List<int>` no longer compiles.
  - **A corrupt or unsupported entry now fails the open, not the read.**
    Every entry is inflated in validation, so one that cannot be inflated
    fails `openBook` and `readBook` even when the book never reads it (a
    stray `__MACOSX/` file, say); before, it failed only if and when it was
    read.
  - DEFLATE is still inflated by `dart:io`'s zlib, now through
    `RawZLibFilter`, fed a chunk at a time so the limits stop it part-way. A
    refused bomb costs a chunk, not the 256 MiB it was stopped at. An invalid
    stream fails with `EpubCorruptArchiveException`; one cut short still
    yields what it holds, without an error, as before.
  - `EpubArchiveTooLargeException` messages give sizes and limits, never an
    entry's file name, which can carry the book's title.
  - The entries of `EpubBookRef.epubArchive()` carry their name, their
    inflated content, and a `size` that is the inflated length rather than
    the header's claim. They no longer carry the ZIP's CRC, file mode,
    modification time, or directory and symlink flags.
  - Only STORE and DEFLATE entries are read, the two methods the EPUB
    container format allows. An entry in any other method, BZIP2 included,
    refuses the book at open with the new
    **`EpubUnsupportedCompressionException`**; before, BZIP2 was read and
    other methods threw `ArchiveException` when read. The
    ZIP encryption flag is ignored; the EPUB container format forbids ZIP
    encryption. An entry with the flag set but its bytes in the clear now
    opens, where it used to throw `FormatException`.
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
    field is gone. `EpubBookRef.epubArchive()` returns a non-null `Archive`.
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
