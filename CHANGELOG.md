# Changelog

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
