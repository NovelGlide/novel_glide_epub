# Changelog

## Unreleased

**Archive size limits.** Every entry point now refuses a ZIP container past
fixed limits, so what one book can cost in memory is bounded: its input
bytes plus its inflated content, each within the limits below.

| Limit | Value |
|---|---|
| Compressed input (the file, or the bytes passed in) | 512 MiB |
| Entries in the archive | 4096 |
| Bytes one entry inflates to | 256 MiB |
| Bytes all entries inflate to | 512 MiB |

- A breach throws **`EpubArchiveTooLargeException`**, a new member of the
  sealed `EpubException` family. So does an archive whose entries' compressed
  sizes add up to more than the file: entries that overlap, sharing one
  stream, would have it inflated once per entry. This is **breaking** for an
  exhaustive `switch` on `EpubException`, which now has to handle it and
  `EpubUnsupportedCompressionException` below.
- The limits are private constants. There is nothing to configure and no
  separate check to call: `openBook`, `readBook` and the two new entry points
  all apply them.
- **New: `openBookFile(String path)` and `readBookFile(String path)`.** They
  check the file's size before reading any of it, so a file past the
  compressed limit is refused without being loaded into memory, then decode
  it as `openBook` / `readBook` do. They bring in `dart:io`, so the package no
  longer compiles for the web.
- **The archive is inflated once, in `openBook`.** The central directory is
  read here, record by record, rather than by `package:archive`'s
  `ZipDirectory.read`, so the entries are counted as they are read, whatever
  count the end record claims, and the one past the limit is refused before
  it is built. Their declared sizes are checked before anything is inflated.
  Then every entry is inflated once, counting the bytes it really produces,
  and abandoned when they cross the per-entry limit or what the total limit
  has left. A header that under-declares its size gets no further than the
  limit; within the limits an entry that inflates past its declared size
  still opens, since writers misstate it in good faith (`package:archive`'s
  `ArchiveFile.string` declares a text's UTF-16 length). Content files are
  read from those inflated entries without inflating again.
- **Behaviour changes that come with the one decode:**
  - `openBook` holds every entry inflated, up to 512 MiB, where it used to
    inflate a content file only when it was read. A stored entry's content
    is a view of the input bytes, so those stay held as well.
  - **A corrupt or unsupported entry now fails the open, not the read.**
    Every entry is inflated in `openBook`, so one that cannot be inflated
    fails `openBook` and `readBook` even when the book never reads it (a
    stray `__MACOSX/` file, say); before, it failed only if and when it was
    read.
  - DEFLATE is still inflated by `dart:io`'s zlib, now through
    `RawZLibFilter`, fed a chunk at a time so the limits stop it part-way.
    Its output is kept as zlib's chunks and joined once at the end, so a
    refused bomb costs at most the 256 MiB entry limit. An invalid stream
    fails with `FormatException`, as before; one cut short still yields
    what it holds, without an error.
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
    encryption.

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
