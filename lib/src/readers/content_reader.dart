import 'package:archive/archive.dart';

import '../entities/epub_content_type.dart';
import '../ref_entities/epub_byte_content_file_ref.dart';
import '../ref_entities/epub_content_file_ref.dart';
import '../ref_entities/epub_content_ref.dart';
import '../ref_entities/epub_text_content_file_ref.dart';
import '../schema/opf/epub_manifest.dart';
import '../schema/opf/epub_manifest_item.dart';
import '../utils/zip_path_resolver.dart';

class ContentReader {
  const ContentReader();

  /// Files every manifest item under its decoded name, in the bucket its
  /// media type belongs to and in `allFiles`.
  ///
  /// The key is the decoded name so a navigation link finds its file however
  /// either side spells it: a manifest may escape a name (`%E7%AC%AC.xhtml`)
  /// that the navigation writes raw (`第.xhtml`), or the other way round.
  /// Two items whose hrefs decode to one name are one file in the archive,
  /// so the later item replaces the earlier, in `allFiles` and in the named
  /// buckets alike.
  EpubContentRef parseContentMap(
      Archive epubArchive, String contentDirectoryPath, EpubManifest manifest) {
    final Map<String, EpubContentFileRef> allFiles =
        <String, EpubContentFileRef>{
      for (final EpubContentFileRef contentFile in manifest.items.map(
          (EpubManifestItem manifestItem) =>
              _readFileRef(epubArchive, contentDirectoryPath, manifestItem)))
        contentFile.fileName: contentFile,
    };

    final Map<String, EpubTextContentFileRef> html =
        <String, EpubTextContentFileRef>{};
    final Map<String, EpubTextContentFileRef> css =
        <String, EpubTextContentFileRef>{};
    final Map<String, EpubByteContentFileRef> images =
        <String, EpubByteContentFileRef>{};
    final Map<String, EpubByteContentFileRef> fonts =
        <String, EpubByteContentFileRef>{};
    for (final EpubContentFileRef contentFile in allFiles.values) {
      switch (contentFile) {
        case EpubTextContentFileRef():
          _textBucketOf(contentFile.contentType,
              html: html, css: css)?[contentFile.fileName] = contentFile;
        case EpubByteContentFileRef():
          _byteBucketOf(contentFile.contentType,
              images: images,
              fonts: fonts)?[contentFile.fileName] = contentFile;
      }
    }

    return EpubContentRef(
      html: Map<String, EpubTextContentFileRef>.unmodifiable(html),
      css: Map<String, EpubTextContentFileRef>.unmodifiable(css),
      images: Map<String, EpubByteContentFileRef>.unmodifiable(images),
      fonts: Map<String, EpubByteContentFileRef>.unmodifiable(fonts),
      allFiles: Map<String, EpubContentFileRef>.unmodifiable(allFiles),
    );
  }

  /// The reference for one manifest item, text or bytes by its media type.
  EpubContentFileRef _readFileRef(Archive epubArchive,
      String contentDirectoryPath, EpubManifestItem manifestItem) {
    final String fileName =
        const ZipPathResolver().decodeHref(manifestItem.href);
    final EpubContentType contentType =
        getContentTypeByContentMimeType(manifestItem.mediaType);
    return _isTextContentType(contentType)
        ? EpubTextContentFileRef(
            epubArchive: epubArchive,
            contentDirectoryPath: contentDirectoryPath,
            fileName: fileName,
            contentType: contentType,
            contentMimeType: manifestItem.mediaType,
          )
        : EpubByteContentFileRef(
            epubArchive: epubArchive,
            contentDirectoryPath: contentDirectoryPath,
            fileName: fileName,
            contentType: contentType,
            contentMimeType: manifestItem.mediaType,
          );
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
      EpubContentType contentType,
      {required Map<String, EpubTextContentFileRef> html,
      required Map<String, EpubTextContentFileRef> css}) {
    switch (contentType) {
      case EpubContentType.xhtml11:
        return html;
      case EpubContentType.css:
        return css;
      default:
        return null;
    }
  }

  /// The named bucket a byte file also belongs in, or null when the type has
  /// no bucket of its own and is reachable only through `allFiles`.
  Map<String, EpubByteContentFileRef>? _byteBucketOf(
      EpubContentType contentType,
      {required Map<String, EpubByteContentFileRef> images,
      required Map<String, EpubByteContentFileRef> fonts}) {
    switch (contentType) {
      case EpubContentType.imageGif:
      case EpubContentType.imageJpeg:
      case EpubContentType.imagePng:
      case EpubContentType.imageSvg:
      case EpubContentType.imageBmp:
        return images;
      case EpubContentType.fontTruetype:
      case EpubContentType.fontOpentype:
        return fonts;
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
