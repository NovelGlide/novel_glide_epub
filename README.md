# novel_glide_epub

EPUB parser for Dart. Used by [NovelGlide](https://github.com/NovelGlide), a
cross-platform EPUB reader.

Pure Dart — no Flutter dependency; it uses `dart:io`, so it does not run on
the web. It reads an EPUB's package document, navigation and content out of
the ZIP container: `EpubReader.readBook` parses every content file,
`EpubReader.openBook` only the structure, leaving each content file to be
parsed when it is read. Both are instance methods on `const EpubReader()`,
and each has a variant that takes a file path.

```dart
import 'package:novel_glide_epub/novel_glide_epub.dart';

const EpubReader reader = EpubReader();

// Whole book, content included.
final EpubBook book = await reader.readBook(bytes);

// Just the structure; each content file is parsed when it is read.
final EpubBookRef bookRef = await reader.openBook(bytes);

// The same from a file on disk, read a chunk at a time, never whole.
final EpubBook fromFile = await reader.readBookFile(path);
final EpubBookRef refFromFile = await reader.openBookFile(path);
```

What this package guards is its own decompression. An entry is inflated
only when it is read, by one inflater that throws
`EpubArchiveTooLargeException` as soon as the entry passes 256 MiB, or the
entries read from one book pass 512 MiB between them, whatever size their
headers declared. Opening a book refuses one over 512 MiB compressed or
over 4096 entries; what sizes the entries declare is not held against it.
The limits cannot be configured, and there is no separate check to call.
An entry that
is damaged, too large, or compressed with a method other than store or
deflate fails when it is read, not when the book is opened.

What that costs in memory:

- **`openBook` / `openBookFile`** read the ZIP's end record and central
  directory, one pass over its records, and of the entries only the
  documents they parse to open the book: no other entry's local header or
  data. An entry is read when it is asked for, local header and all,
  inflated into memory, held once, and kept for as long as the
  `EpubBookRef` lives; one never asked for is never read. `openBook` holds the
  bytes it was given; an `EpubBookRef` from `openBookFile` holds only the
  path, opening the file for each read and closing it after, so there is
  nothing to close.
- **`readBook` / `readBookFile`** read every entry the `EpubBook` holds
  through the same inflater, each once, into the `EpubBook` they return.

## Origin

A fork of [`epubx`](https://github.com/rbcprolabs/epubx.dart) (itself a fork of
`epub`), vendored into the NovelGlide app in 2025 and extracted here so it can
carry its own tests and CI. `LICENSE` is the original MIT licence and is
unchanged — see [Licence](#licence).

Changes since the fork point, all driven by books that failed to open in
production:

- **Nav base-path resolution** — a relative `href` in an EPUB 3 nav document no
  longer has its first path segment dropped, so a book whose OPF sits at the
  ZIP root is not reported as corrupt.

## Why the name

`epubx` is taken on pub.dev by the upstream package. This fork diverges from it
and is maintained for one application's needs, so it carries its own name
rather than shadowing one it is no longer identical to.

Not published to pub.dev; consumed by git reference.

## Status

**Coverage: 100%** (1546 / 1546 lines, 708 tests), up from 21% at extraction,
when the suite was seven test cases written to pin two specific bugs and forty
of the fifty-five files had never been executed at all.

**The writing side is covered, and lossy in named ways.** `epub_writer.dart`
and `writers/` serialise an EPUB back out. Nothing in NovelGlide writes EPUBs,
so they exist to keep the capability rather than to serve a caller — but they
are no longer unverified: every line is executed, the read → write → read trip
is asserted as whole-`EpubBook` equality, and each serialiser has direct tests
for its own branches.

What those tests pin is that the trip loses specific things. Each item below
has a test that fails if the behaviour changes, so they are recorded rather
than hidden:

- The container is written with a constant `OEBPS/content.opf` root path, so a
  book whose OPF sat anywhere else is written unreadable.
- Spine linearity inverts on every trip: `readSpine` maps both an absent
  `linear` and `linear="no"` to `isLinear = true`, and the writer maps `true`
  back to `"yes"`. The pair has no fixed point.
- `page-progression-direction` and the manifest's `properties` and fallback
  attributes have no writer, so a right-to-left book and an EPUB3 nav
  declaration do not survive.
- `EpubNavigationWriter` has no caller at all — `EpubWriter` carries the NCX
  through as a raw content file — and what it writes is not quite NCX: the
  `docTitle` lacks the `<text>` wrapper the reader requires, so it reads back
  empty; nested `navPoint`s are not written; and an EPUB3 heading entry,
  which links nowhere, is left out because an NCX `navPoint` must link.

Treat the writer as able to round-trip a book this parser has just read out of
a conventional EPUB2 container, and not yet as a general EPUB serialiser.

**The lint is this org's set** — `dart_lints`, run with `dart run dart_lints`;
`dart_lints.yaml` holds this package's half and `analysis_options.yaml` the
stock-analyzer lints it does not take. `dart run dart_lints` reports **0
issues**, including infos, and there is no `errors: ignore` entry or
`// ignore:` comment anywhere in the package. The one place this package's
selection differs from the app's is imports: the app enables
`always_use_package_imports`, this package does not (the reason is recorded
beside it in `analysis_options.yaml`) and enables `prefer_relative_imports`
instead.

## Development

```bash
dart pub get
dart test
dart test --coverage=coverage
dart run dart_lints
```

**Releasing** is bumping `version:` in `pubspec.yaml`. The push to `main` that
carries the bump is tagged `v<version>` by `.github/workflows/release-tag.yml`,
once format, lint and the test suite pass on that commit. Tags are only ever
added, never moved, so a version number always means one tree.

Because a tag cannot be taken back, **bumping the version is the last step,
not the first**:

1. Land the change on `main` without touching `version:`. Pushes that do not
   bump the version are never tagged.
2. In the NovelGlide app, point the dependency at that commit (`ref: <sha>`)
   and get the app's full suite, coverage and review green against it. A
   problem found here is fixed in this package, still unreleased.
3. Only then bump `version:`; the workflow tags it, and the app PR switches
   its `ref:` from the sha to the tag.

A package change the app has never compiled against is not ready to be a
version, however green this repo's own suite is.

## Licence

MIT, Copyright (c) 2017 Colin Nelson. The original notice is preserved verbatim
in `LICENSE`; this fork adds no licence terms of its own.
