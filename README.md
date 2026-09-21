# novel_glide_epub

EPUB parser for Dart. Used by [NovelGlide](https://github.com/NovelGlide), a
cross-platform EPUB reader.

Pure Dart — no Flutter dependency. It reads an EPUB's package document,
navigation and content out of the ZIP container, either eagerly
(`EpubReader.readBook`) or lazily by reference (`EpubReader.openBook`).

```dart
import 'package:novel_glide_epub/novel_glide_epub.dart';

// Whole book, content included.
final EpubBook book = await EpubReader.readBook(bytes);

// Just the structure; each content file is read on demand.
final EpubBookRef bookRef = await EpubReader.openBook(bytes);
```

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

**Coverage: 99.4%** (1504 / 1513 lines), up from 21% at extraction, when the
suite was seven test cases written to pin two specific bugs and forty of the
fifty-five files had never been executed at all. The nine remaining lines are
in `root_file_path_reader.dart`, `chapter_reader.dart`, `package_reader.dart`
and `navigation_reader.dart`.

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
  `linear` and `linear="no"` to `IsLinear = true`, and the writer maps `true`
  back to `"yes"`. The pair has no fixed point.
- A book with no `<guide>`, and a spine with no `toc`, cannot be written at
  all — both writers dereference what the reader leaves null.
- `page-progression-direction` and the manifest's `properties` and fallback
  attributes have no writer, so a right-to-left book and an EPUB3 nav
  declaration do not survive.
- `EpubNavigationWriter` has no caller at all — `EpubWriter` carries the NCX
  through as a raw content file — and what it writes is not quite NCX: the
  `docTitle` lacks the `<text>` wrapper the reader requires, so it reads back
  empty, and nested `navPoint`s are not written.

Treat the writer as able to round-trip a book this parser has just read out of
a conventional EPUB2 container, and not yet as a general EPUB serialiser.

**The lint is this org's set** — `dart_lints`, run with `dart run dart_lints`;
`dart_lints.yaml` holds this package's half and `analysis_options.yaml` the
stock-analyzer lints it does not take. One finding is left on purpose, and it
is named in the code: `EpubReader` is a static-only class because `readBook`
and `openBook` are the entry points the NovelGlide app calls by name, and
making them instance calls would be a breaking change across two repositories.

Four stock lints are held out with their reasons in `analysis_options.yaml` —
the PascalCase public members and the SCREAMING_CASE enum values carried over
from upstream, the `xml` package's deprecated `.text` (where `value` versus
`innerText` is a parsing decision, not a substitution), and two findings inside
`ZipPathResolver.combine`, which a pending fix rewrites.

## Development

```bash
dart pub get
dart test
dart test --coverage=coverage
```

## Licence

MIT, Copyright (c) 2017 Colin Nelson. The original notice is preserved verbatim
in `LICENSE`; this fork adds no licence terms of its own.
