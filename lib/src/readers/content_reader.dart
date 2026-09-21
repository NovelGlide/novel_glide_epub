import '../entities/epub_content_type.dart';
import '../ref_entities/epub_book_ref.dart';
import '../ref_entities/epub_byte_content_file_ref.dart';
import '../ref_entities/epub_content_ref.dart';
import '../ref_entities/epub_text_content_file_ref.dart';
import '../schema/opf/epub_manifest_item.dart';

class ContentReader {
  const ContentReader();

  EpubContentRef parseContentMap(EpubBookRef bookRef) {
    // The five buckets are initialised by `EpubContentRef`'s own constructor;
    // re-assigning them here was a no-op.
    final EpubContentRef result = EpubContentRef();

    for (EpubManifestItem manifestItem in bookRef.Schema!.Package!.Manifest!.Items!) {
      _addManifestItem(result, bookRef, manifestItem);
    }
    return result;
  }

  /// Files the manifest with the bucket its media type belongs to, plus
  /// `AllFiles`.
  ///
  /// The bucket keys stay as the manifest wrote them while `FileName` is
  /// percent-decoded, which is the mismatch a manifest with escaped hrefs
  /// runs into downstream.
  void _addManifestItem(EpubContentRef result, EpubBookRef bookRef,
      EpubManifestItem manifestItem) {
    final String fileName = manifestItem.Href!;
    final String contentMimeType = manifestItem.MediaType!;
    final EpubContentType contentType = getContentTypeByContentMimeType(contentMimeType);

    if (_isTextContentType(contentType)) {
      final EpubTextContentFileRef contentFile = EpubTextContentFileRef(bookRef)
        ..FileName = Uri.decodeFull(fileName)
        ..ContentMimeType = contentMimeType
        ..ContentType = contentType;
      _textBucketOf(result, contentType)?[fileName] = contentFile;
      result.AllFiles![fileName] = contentFile;
    } else {
      final EpubByteContentFileRef contentFile = EpubByteContentFileRef(bookRef)
        ..FileName = Uri.decodeFull(fileName)
        ..ContentMimeType = contentMimeType
        ..ContentType = contentType;
      _byteBucketOf(result, contentType)?[fileName] = contentFile;
      result.AllFiles![fileName] = contentFile;
    }
  }

  /// Whether a content type is read as text; everything else is read as bytes.
  bool _isTextContentType(EpubContentType contentType) {
    switch (contentType) {
      case EpubContentType.XHTML_1_1:
      case EpubContentType.CSS:
      case EpubContentType.OEB1_DOCUMENT:
      case EpubContentType.OEB1_CSS:
      case EpubContentType.XML:
      case EpubContentType.DTBOOK:
      case EpubContentType.DTBOOK_NCX:
        return true;
      default:
        return false;
    }
  }

  /// The named bucket a text file also belongs in, or null when the type has
  /// no bucket of its own and is reachable only through `AllFiles`.
  Map<String, EpubTextContentFileRef>? _textBucketOf(
      EpubContentRef result, EpubContentType contentType) {
    switch (contentType) {
      case EpubContentType.XHTML_1_1:
        return result.Html;
      case EpubContentType.CSS:
        return result.Css;
      default:
        return null;
    }
  }

  /// The named bucket a byte file also belongs in, or null when the type has
  /// no bucket of its own and is reachable only through `AllFiles`.
  Map<String, EpubByteContentFileRef>? _byteBucketOf(
      EpubContentRef result, EpubContentType contentType) {
    switch (contentType) {
      case EpubContentType.IMAGE_GIF:
      case EpubContentType.IMAGE_JPEG:
      case EpubContentType.IMAGE_PNG:
      case EpubContentType.IMAGE_SVG:
      case EpubContentType.IMAGE_BMP:
        return result.Images;
      case EpubContentType.FONT_TRUETYPE:
      case EpubContentType.FONT_OPENTYPE:
        return result.Fonts;
      default:
        return null;
    }
  }

  EpubContentType getContentTypeByContentMimeType(String contentMimeType) {
    switch (contentMimeType.toLowerCase()) {
      case 'application/xhtml+xml':
      case 'text/html':
        return EpubContentType.XHTML_1_1;
      case 'application/x-dtbook+xml':
        return EpubContentType.DTBOOK;
      case 'application/x-dtbncx+xml':
        return EpubContentType.DTBOOK_NCX;
      case 'text/x-oeb1-document':
        return EpubContentType.OEB1_DOCUMENT;
      case 'application/xml':
        return EpubContentType.XML;
      case 'text/css':
        return EpubContentType.CSS;
      case 'text/x-oeb1-css':
        return EpubContentType.OEB1_CSS;
      case 'image/gif':
        return EpubContentType.IMAGE_GIF;
      case 'image/jpeg':
        return EpubContentType.IMAGE_JPEG;
      case 'image/png':
        return EpubContentType.IMAGE_PNG;
      case 'image/svg+xml':
        return EpubContentType.IMAGE_SVG;
      case 'image/bmp':
        return EpubContentType.IMAGE_BMP;
      case 'font/truetype':
        return EpubContentType.FONT_TRUETYPE;
      case 'font/opentype':
        return EpubContentType.FONT_OPENTYPE;
      case 'application/vnd.ms-opentype':
        return EpubContentType.FONT_OPENTYPE;
      default:
        return EpubContentType.OTHER;
    }
  }
}
