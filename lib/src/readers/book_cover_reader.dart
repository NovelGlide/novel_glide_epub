import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:image/image.dart' as images;

import '../epub_exception.dart';
import '../ref_entities/epub_book_ref.dart';
import '../ref_entities/epub_byte_content_file_ref.dart';
import '../schema/opf/epub_manifest_item.dart';
import '../schema/opf/epub_metadata_meta.dart';
import '../utils/zip_path_resolver.dart';

class BookCoverReader {
  const BookCoverReader();

  Future<images.Image?> readBookCover(EpubBookRef bookRef) async {
    final EpubMetadataMeta? coverMetaItem = _coverMetaItemOf(bookRef);
    if (coverMetaItem == null) {
      return null;
    }
    if (coverMetaItem.content.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB metadata: cover item content is missing.');
    }

    final EpubManifestItem? coverManifestItem =
        _manifestItemWithId(bookRef, coverMetaItem.content);
    if (coverManifestItem == null) {
      throw EpubUnresolvedReferenceException(
          'Incorrect EPUB manifest: item with ID = "${coverMetaItem.content}" is missing.');
    }

    final EpubByteContentFileRef? coverImageContentFileRef =
        _coverImageOf(bookRef, coverManifestItem.href);
    if (coverImageContentFileRef == null) {
      throw EpubUnresolvedReferenceException(
          'Incorrect EPUB manifest: item with href = "${coverManifestItem.href}" is missing.');
    }

    final Uint8List coverImageContent =
        await coverImageContentFileRef.readContentAsBytes();
    final images.Image? retval = images.decodeImage(coverImageContent);
    return retval;
  }

  /// The RAW bytes of the cover image entry, WITHOUT decoding — for callers
  /// that want to defer decode to a bounded surface (e.g. `Image.memory` with
  /// `cacheWidth` on the UI isolate). Returns null when no cover is declared or
  /// the declared cover entry is missing/broken; unlike [readBookCover] it
  /// never throws on a malformed cover, so a book with a bad cover stays
  /// openable.
  ///
  /// Resolves the cover href via BOTH conventions: the EPUB2
  /// `<meta name="cover">` → manifest-item-by-id path, and the EPUB3 manifest
  /// item flagged `properties="cover-image"` (or id `cover` / `cover-image`).
  Future<Uint8List?> readBookCoverBytes(EpubBookRef bookRef) async {
    final String? coverHref =
        _coverHrefFromMetadata(bookRef) ?? _coverHrefFromManifest(bookRef);
    if (coverHref == null) {
      return null;
    }

    final EpubByteContentFileRef? coverImageContentFileRef =
        _coverImageOf(bookRef, coverHref);
    if (coverImageContentFileRef == null) {
      return null;
    }

    try {
      return await coverImageContentFileRef.readContentAsBytes();
    } on EpubMissingArchiveEntryException {
      // The one failure `readContentAsBytes` raises: the manifest declares a
      // cover the ZIP does not carry. Treat it as "no cover" rather than
      // failing the whole open. Deliberately this narrow — anything else is a
      // defect in this package or in a dependency, and swallowing it here
      // would hide it behind a book that merely looks coverless.
      return null;
    }
  }

  /// The image a manifest [href] names. The images map is keyed by decoded
  /// name, and the manifest href may be escaped.
  EpubByteContentFileRef? _coverImageOf(EpubBookRef bookRef, String href) =>
      bookRef.content.images[const ZipPathResolver().decodeHref(href)];

  /// The EPUB2 `<meta name="cover">`, whose content is a manifest item id.
  EpubMetadataMeta? _coverMetaItemOf(EpubBookRef bookRef) =>
      bookRef.schema.package.metadata.metaItems.firstWhereOrNull(
          (EpubMetadataMeta metaItem) =>
              metaItem.name?.toLowerCase() == 'cover');

  EpubManifestItem? _manifestItemWithId(EpubBookRef bookRef, String id) =>
      bookRef.schema.package.manifest.items.firstWhereOrNull(
          (EpubManifestItem manifestItem) =>
              manifestItem.id.toLowerCase() == id.toLowerCase());

  /// EPUB2 cover href: a `<meta name="cover">` whose content is a manifest
  /// item id.
  String? _coverHrefFromMetadata(EpubBookRef bookRef) {
    final String? coverId = _coverMetaItemOf(bookRef)?.content;
    if (coverId == null || coverId.isEmpty) {
      return null;
    }

    return _manifestItemWithId(bookRef, coverId)?.href;
  }

  /// EPUB3 cover href: a manifest image item flagged as the cover via
  /// `properties` (or a conventional `cover` / `cover-image` id).
  String? _coverHrefFromManifest(EpubBookRef bookRef) =>
      bookRef.schema.package.manifest.items
          .firstWhereOrNull(_isCoverImageItem)
          ?.href;

  bool _isCoverImageItem(EpubManifestItem item) =>
      _namesCover(item) && _isImage(item);

  bool _namesCover(EpubManifestItem item) =>
      _isCoverName(item.id) || _isCoverName(item.properties);

  bool _isCoverName(String? value) {
    final String? name = value?.toLowerCase();
    return name == 'cover' || name == 'cover-image';
  }

  bool _isImage(EpubManifestItem item) =>
      item.mediaType.toLowerCase().startsWith('image/');
}
