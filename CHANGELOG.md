# Changelog

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
