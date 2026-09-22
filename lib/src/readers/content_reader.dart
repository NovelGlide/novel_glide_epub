import '../entities/epub_content_type.dart';
import '../ref_entities/epub_book_ref.dart';
import '../ref_entities/epub_byte_content_file_ref.dart';
import '../ref_entities/epub_content_ref.dart';
import '../ref_entities/epub_text_content_file_ref.dart';
import '../schema/opf/epub_manifest_item.dart';
import '../utils/zip_path_resolver.dart';

class ContentReader {
  const ContentReader();

  EpubContentRef parseContentMap(EpubBookRef bookRef) {
    final EpubContentRef result = EpubContentRef();

    for (EpubManifestItem manifestItem
        in bookRef.schema!.package!.manifest!.items!) {
      _addManifestItem(result, bookRef, manifestItem);
    }
    return result;
  }

  /// Files the manifest with the bucket its media type belongs to, plus
  /// `allFiles`.
  ///
  /// The bucket keys stay as the manifest wrote them while `fileName` is
  /// percent-decoded. A navigation that links a file by the manifest's own
  /// spelling, or escapes what the manifest writes raw, finds it; one that
  /// writes raw what the manifest escapes does not.
  void _addManifestItem(EpubContentRef result, EpubBookRef bookRef,
      EpubManifestItem manifestItem) {
    final String fileName = manifestItem.href!;
    final String contentMimeType = manifestItem.mediaType!;
    final EpubContentType contentType =
        getContentTypeByContentMimeType(contentMimeType);

    if (_isTextContentType(contentType)) {
      final EpubTextContentFileRef contentFile = EpubTextContentFileRef(bookRef)
        ..fileName = const ZipPathResolver().decodeHref(fileName)
        ..contentMimeType = contentMimeType
        ..contentType = contentType;
      _textBucketOf(result, contentType)?[fileName] = contentFile;
      result.allFiles![fileName] = contentFile;
    } else {
      final EpubByteContentFileRef contentFile = EpubByteContentFileRef(bookRef)
        ..fileName = const ZipPathResolver().decodeHref(fileName)
        ..contentMimeType = contentMimeType
        ..contentType = contentType;
      _byteBucketOf(result, contentType)?[fileName] = contentFile;
      result.allFiles![fileName] = contentFile;
    }
  }

  /// Whether a content type is read as text; everything else is read as bytes.
  bool _isTextContentType(EpubContentType contentType) {
    switch (contentType) {
      case EpubContentType.xhtml11:
      case EpubContentType.css:
      case EpubContentType.oeb1Document:
      case EpubContentType.oeb1Css:
      case EpubContentType.xml:
      case EpubContentType.dtbook:
      case EpubContentType.dtbookNcx:
        return true;
      default:
        return false;
    }
  }

  /// The named bucket a text file also belongs in, or null when the type has
  /// no bucket of its own and is reachable only through `allFiles`.
  Map<String, EpubTextContentFileRef>? _textBucketOf(
      EpubContentRef result, EpubContentType contentType) {
    switch (contentType) {
      case EpubContentType.xhtml11:
        return result.html;
      case EpubContentType.css:
        return result.css;
      default:
        return null;
    }
  }

  /// The named bucket a byte file also belongs in, or null when the type has
  /// no bucket of its own and is reachable only through `allFiles`.
  Map<String, EpubByteContentFileRef>? _byteBucketOf(
      EpubContentRef result, EpubContentType contentType) {
    switch (contentType) {
      case EpubContentType.imageGif:
      case EpubContentType.imageJpeg:
      case EpubContentType.imagePng:
      case EpubContentType.imageSvg:
      case EpubContentType.imageBmp:
        return result.images;
      case EpubContentType.fontTruetype:
      case EpubContentType.fontOpentype:
        return result.fonts;
      default:
        return null;
    }
  }

  EpubContentType getContentTypeByContentMimeType(String contentMimeType) {
    switch (contentMimeType.toLowerCase()) {
      case 'application/xhtml+xml':
      case 'text/html':
        return EpubContentType.xhtml11;
      case 'application/x-dtbook+xml':
        return EpubContentType.dtbook;
      case 'application/x-dtbncx+xml':
        return EpubContentType.dtbookNcx;
      case 'text/x-oeb1-document':
        return EpubContentType.oeb1Document;
      case 'application/xml':
        return EpubContentType.xml;
      case 'text/css':
        return EpubContentType.css;
      case 'text/x-oeb1-css':
        return EpubContentType.oeb1Css;
      case 'image/gif':
        return EpubContentType.imageGif;
      case 'image/jpeg':
        return EpubContentType.imageJpeg;
      case 'image/png':
        return EpubContentType.imagePng;
      case 'image/svg+xml':
        return EpubContentType.imageSvg;
      case 'image/bmp':
        return EpubContentType.imageBmp;
      case 'font/truetype':
        return EpubContentType.fontTruetype;
      case 'font/opentype':
        return EpubContentType.fontOpentype;
      case 'application/vnd.ms-opentype':
        return EpubContentType.fontOpentype;
      default:
        return EpubContentType.other;
    }
  }
}
