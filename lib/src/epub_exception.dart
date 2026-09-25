/// The base of every failure this package raises on purpose.
///
/// Catching [EpubException] means exactly one thing: *this book is not a
/// readable EPUB*. A ZIP container that fails to decode is one of these:
/// the reader turns `package:archive`'s `ArchiveException` and zlib's
/// `FormatException` into [EpubCorruptArchiveException]. Anything else that
/// escapes a reader — a `TypeError`, a `StateError` — is a defect in this
/// package or in a dependency, and the two are deliberately not merged: a
/// caller that shows "this file is damaged" for a parser bug hides the bug
/// forever.
///
/// One exception to that. The reader hands `package:archive` only streams
/// that refuse a read past their end as [EpubCorruptArchiveException], but
/// two of its parsers copy bytes into a stream of their own, which does not:
/// a zip64 extra field in a central-directory record, and the extra field
/// of an encrypted entry's local header. One damaged so that it reads past
/// its own end throws a `RangeError` from inside `package:archive`, and it
/// escapes as it is. The file is damaged, not the parser, but a `RangeError`
/// cannot be told apart from a defect, so it is not caught.
///
/// The family is `sealed`, so a caller can `switch` on the cause and a new
/// cause cannot be added without every such `switch` being told about it.
sealed class EpubException implements Exception {
  const EpubException(this.message);

  /// What failed, in the parser's own words. Not localised, and not for
  /// display — a UI shows its own text and uses the runtime type to pick it.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The file is not a ZIP container, or its container is damaged: a
/// structure `package:archive` cannot parse, a structure that reaches past
/// the end of the file or has a negative length, entries whose compressed
/// data overlap, or an entry whose deflate stream zlib rejects.
///
/// Raised when the book is opened, whether or not the package document
/// points at the damaged entry.
final class EpubCorruptArchiveException extends EpubException {
  const EpubCorruptArchiveException(super.message);
}

/// A file the package document points at is absent from the ZIP container.
///
/// The archive is incomplete or truncated: the EPUB says the file is there
/// and it is not.
final class EpubMissingArchiveEntryException extends EpubException {
  const EpubMissingArchiveEntryException(super.message);
}

/// The package document declares an EPUB version this parser does not read.
final class EpubUnsupportedVersionException extends EpubException {
  const EpubUnsupportedVersionException(super.message);
}

/// An XML element the format requires is absent from a document that is
/// otherwise well-formed.
///
/// The file parsed as XML; what it contains is not the document it claims to
/// be.
final class EpubMissingElementException extends EpubException {
  const EpubMissingElementException(super.message);
}

/// An attribute or text value the format requires is absent or empty on an
/// element that is itself present.
final class EpubMissingValueException extends EpubException {
  const EpubMissingValueException(super.message);
}

/// An id or href that one part of the package points at resolves to nothing
/// in the part that should declare it.
///
/// Each half is well-formed on its own — the manifest, the spine and the
/// navigation document simply disagree about what exists.
final class EpubUnresolvedReferenceException extends EpubException {
  const EpubUnresolvedReferenceException(super.message);
}

/// An entry of the ZIP container is compressed with a method other than the
/// two an EPUB container allows, store and deflate.
///
/// Raised when the book is opened, whether or not the package document
/// points at the entry.
final class EpubUnsupportedCompressionException extends EpubException {
  const EpubUnsupportedCompressionException(super.message);
}

/// The ZIP container is past one of the parser's fixed limits: the file's
/// compressed size, the number of entries, or the bytes one entry or the
/// whole archive inflates to.
///
/// Raised before any of the book is parsed, and at the latest part-way
/// through inflating the entry that crosses the limit, so a decompression
/// bomb is refused before it is held in memory. The file may be a
/// well-formed EPUB that the parser declines to open.
final class EpubArchiveTooLargeException extends EpubException {
  const EpubArchiveTooLargeException(super.message);
}
