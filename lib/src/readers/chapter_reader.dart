import '../epub_exception.dart';
import '../ref_entities/epub_book_ref.dart';
import '../ref_entities/epub_chapter_ref.dart';
import '../ref_entities/epub_text_content_file_ref.dart';
import '../schema/navigation/epub_navigation_point.dart';
import '../utils/unmodifiable_iterable.dart';
import '../utils/zip_path_resolver.dart';

class ChapterReader {
  const ChapterReader();

  List<EpubChapterRef> getChapters(EpubBookRef bookRef) {
    return getChaptersImpl(bookRef, bookRef.schema.navigation.navMap.points);
  }

  List<EpubChapterRef> getChaptersImpl(
      EpubBookRef bookRef, List<EpubNavigationPoint> navigationPoints) {
    final List<EpubChapterRef> result = <EpubChapterRef>[];
    for (EpubNavigationPoint navigationPoint in navigationPoints) {
      // A navigation point with no content source points nowhere, so it is
      // skipped rather than refused.
      final String? source = navigationPoint.content.source;
      if (source == null) {
        continue;
      }
      result.add(_readChapterRef(bookRef, navigationPoint, source));
    }
    return result;
  }

  EpubChapterRef _readChapterRef(EpubBookRef bookRef,
      EpubNavigationPoint navigationPoint, String contentSource) {
    final int anchorCharIndex = contentSource.indexOf('#');
    // The content maps are keyed by decoded name, so the link is decoded too:
    // a navigation may escape a name the manifest writes raw, or the other
    // way round.
    final String contentFileName = const ZipPathResolver().decodeHref(
        anchorCharIndex == -1
            ? contentSource
            : contentSource.substring(0, anchorCharIndex));
    final String? anchor = anchorCharIndex == -1
        ? null
        : contentSource.substring(anchorCharIndex + 1);

    final EpubTextContentFileRef? contentFileRef =
        bookRef.content.html[contentFileName];
    if (contentFileRef == null) {
      throw EpubUnresolvedReferenceException(
          'Incorrect EPUB manifest: item with href = "$contentFileName" is missing.');
    }

    final Map<String, EpubTextContentFileRef> splitSiblings =
        _splitSiblingsOf(bookRef, contentFileName);
    return EpubChapterRef(
      epubTextContentFileRef: contentFileRef,
      title: navigationPoint.navigationLabels.first.text,
      contentFileName: contentFileName,
      anchor: anchor,
      subChapters:
          getChaptersImpl(bookRef, navigationPoint.childNavigationPoints)
              .toUnmodifiableList(),
      otherTextContentFileRefs: splitSiblings.values.toUnmodifiableList(),
      otherContentFileNames: splitSiblings.keys.toUnmodifiableList(),
    );
  }

  /// Some producers cut one source document into `_split_`-suffixed siblings.
  /// The navigation names only the first, so the chapter carries the rest of
  /// the family with it, in manifest order.
  Map<String, EpubTextContentFileRef> _splitSiblingsOf(
      EpubBookRef bookRef, String contentFileName) {
    if (!contentFileName.contains('_split_')) {
      return const <String, EpubTextContentFileRef>{};
    }
    final String fileNamePart = contentFileName.split('_split_')[0];
    return <String, EpubTextContentFileRef>{
      for (final MapEntry<String, EpubTextContentFileRef> entry
          in bookRef.content.html.entries)
        if (entry.key.contains(fileNamePart) && entry.key != contentFileName)
          entry.key: entry.value,
    };
  }
}
