import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:image/image.dart' as images;

import '../epub_exception.dart';
import '../ref_entities/epub_book_ref.dart';
import '../ref_entities/epub_byte_content_file_ref.dart';
import '../schema/opf/epub_manifest_item.dart';
import '../schema/opf/epub_metadata_meta.dart';

class BookCoverReader {
  const BookCoverReader();

  Future<images.Image?> readBookCover(EpubBookRef bookRef) async {
    var metaItems = bookRef.Schema!.Package!.Metadata!.MetaItems;
    if (metaItems == null || metaItems.isEmpty) return null;

    var coverMetaItem = metaItems.firstWhereOrNull(
        (EpubMetadataMeta metaItem) =>
            metaItem.Name != null && metaItem.Name!.toLowerCase() == 'cover');
    if (coverMetaItem == null) return null;
    if (coverMetaItem.Content == null || coverMetaItem.Content!.isEmpty) {
      throw const EpubMissingValueException(
          'Incorrect EPUB metadata: cover item content is missing.');
    }

    var coverManifestItem = bookRef.Schema!.Package!.Manifest!.Items!
        .firstWhereOrNull((EpubManifestItem manifestItem) =>
            manifestItem.Id!.toLowerCase() ==
            coverMetaItem.Content!.toLowerCase());
    if (coverManifestItem == null) {
      throw EpubUnresolvedReferenceException(
          'Incorrect EPUB manifest: item with ID = "${coverMetaItem.Content}" is missing.');
    }

    EpubByteContentFileRef? coverImageContentFileRef;
    if (!bookRef.Content!.Images!.containsKey(coverManifestItem.Href)) {
      throw EpubUnresolvedReferenceException(
          'Incorrect EPUB manifest: item with href = "${coverManifestItem.Href}" is missing.');
    }

    coverImageContentFileRef = bookRef.Content!.Images![coverManifestItem.Href];
    var coverImageContent =
        await coverImageContentFileRef!.readContentAsBytes();
    var retval = images.decodeImage(Uint8List.fromList(coverImageContent));
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
    var coverHref =
        _coverHrefFromMetadata(bookRef) ?? _coverHrefFromManifest(bookRef);
    if (coverHref == null) return null;

    var images = bookRef.Content?.Images;
    if (images == null || !images.containsKey(coverHref)) return null;

    var coverImageContentFileRef = images[coverHref];
    if (coverImageContentFileRef == null) return null;

    try {
      return await coverImageContentFileRef.readContentAsBytes();
    } on Exception {
      // A declared-but-broken archive entry: treat as "no cover" rather than
      // failing the whole open. Still `on Exception` rather than
      // `on EpubException`, because the throws it has to catch live in
      // `ref_entities/epub_content_file_ref.dart` and are still untyped.
      return null;
    }
  }

  /// EPUB2 cover href: a `<meta name="cover">` whose content is a manifest
  /// item id.
  String? _coverHrefFromMetadata(EpubBookRef bookRef) {
    var coverId = _metaItemsOf(bookRef)
        .firstWhereOrNull((EpubMetadataMeta metaItem) =>
            metaItem.Name?.toLowerCase() == 'cover')
        ?.Content;
    if (coverId == null || coverId.isEmpty) return null;

    return _manifestItemsOf(bookRef)
        .firstWhereOrNull((EpubManifestItem manifestItem) =>
            manifestItem.Id?.toLowerCase() == coverId.toLowerCase())
        ?.Href;
  }

  /// EPUB3 cover href: a manifest image item flagged as the cover via
  /// `properties` (or a conventional `cover` / `cover-image` id).
  String? _coverHrefFromManifest(EpubBookRef bookRef) =>
      _manifestItemsOf(bookRef).firstWhereOrNull(_isCoverImageItem)?.Href;

  bool _isCoverImageItem(EpubManifestItem item) =>
      item.Href != null && _namesCover(item) && _isImage(item);

  bool _namesCover(EpubManifestItem item) =>
      _isCoverName(item.Id) || _isCoverName(item.Properties);

  bool _isCoverName(String? value) {
    var name = value?.toLowerCase();
    return name == 'cover' || name == 'cover-image';
  }

  bool _isImage(EpubManifestItem item) =>
      item.MediaType?.toLowerCase().startsWith('image/') == true;

  List<EpubMetadataMeta> _metaItemsOf(EpubBookRef bookRef) =>
      bookRef.Schema?.Package?.Metadata?.MetaItems ??
      const <EpubMetadataMeta>[];

  List<EpubManifestItem> _manifestItemsOf(EpubBookRef bookRef) =>
      bookRef.Schema?.Package?.Manifest?.Items ?? const <EpubManifestItem>[];
}
