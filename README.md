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

**The source is still upstream's style** — `var`, PascalCase fields, few
explicit types. The lint set here is deliberately `package:lints/recommended`
rather than this org's stricter one: turning the strict set on before the test
suite exists would bury real findings under a few hundred style violations.
Aligning the style is a separate pass, after coverage.

## Development

```bash
dart pub get
dart test
dart test --coverage=coverage
```

## Licence

MIT, Copyright (c) 2017 Colin Nelson. The original notice is preserved verbatim
in `LICENSE`; this fork adds no licence terms of its own.
