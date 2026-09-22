import '../epub_exception.dart';
import '../ref_entities/epub_book_ref.dart';
import '../ref_entities/epub_chapter_ref.dart';
import '../schema/navigation/epub_navigation_point.dart';
import '../utils/zip_path_resolver.dart';

class ChapterReader {
  const ChapterReader();

  List<EpubChapterRef> getChapters(EpubBookRef bookRef) {
    if (bookRef.schema!.navigation == null) {
      return <EpubChapterRef>[];
    }
    return getChaptersImpl(
        bookRef, bookRef.schema!.navigation!.navMap!.points!);
  }

  List<EpubChapterRef> getChaptersImpl(
      EpubBookRef bookRef, List<EpubNavigationPoint> navigationPoints) {
    final List<EpubChapterRef> result = <EpubChapterRef>[];
    for (EpubNavigationPoint navigationPoint in navigationPoints) {
      // A navigation point with no content source points nowhere, so it is
      // skipped rather than refused.
      final String? source = navigationPoint.content?.source;
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
    final String source = anchorCharIndex == -1
        ? contentSource
        : contentSource.substring(0, anchorCharIndex);
    // The content maps are keyed by the href as the manifest wrote it, so the
    // navigation's own spelling is tried first; its decoded form covers a
    // navigation that escapes what the manifest writes raw.
    final String contentFileName = bookRef.content!.html!.containsKey(source)
        ? source
        : const ZipPathResolver().decodeHref(source);
    final String? anchor = anchorCharIndex == -1
        ? null
        : contentSource.substring(anchorCharIndex + 1);

    if (!bookRef.content!.html!.containsKey(contentFileName)) {
      throw EpubUnresolvedReferenceException(
          'Incorrect EPUB manifest: item with href = "$contentFileName" is missing.');
    }

    final EpubChapterRef chapterRef =
        EpubChapterRef(bookRef.content!.html![contentFileName])
          ..contentFileName = contentFileName
          ..anchor = anchor
          ..title = navigationPoint.navigationLabels!.first.text
          ..subChapters =
              getChaptersImpl(bookRef, navigationPoint.childNavigationPoints!);
    _addSplitSiblings(bookRef, chapterRef, contentFileName);
    return chapterRef;
  }

  /// Some producers cut one source document into `_split_`-suffixed siblings.
  /// The navigation names only the first, so the chapter carries the rest of
  /// the family with it.
  void _addSplitSiblings(
      EpubBookRef bookRef, EpubChapterRef chapterRef, String contentFileName) {
    if (!chapterRef.contentFileName!.contains('_split_')) {
      return;
    }
    final String fileNamePart = chapterRef.contentFileName!.split('_split_')[0];
    for (String fileName in bookRef.content!.html!.keys) {
      if (fileName.contains(fileNamePart) && fileName != contentFileName) {
        chapterRef.otherTextContentFileRefs
            .add(bookRef.content!.html![fileName]!);
        chapterRef.otherContentFileNames.add(fileName);
      }
    }
  }
}
