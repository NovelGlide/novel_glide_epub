import '../epub_exception.dart';
import '../ref_entities/epub_book_ref.dart';
import '../ref_entities/epub_chapter_ref.dart';
import '../schema/navigation/epub_navigation_point.dart';

class ChapterReader {
  const ChapterReader();

  List<EpubChapterRef> getChapters(EpubBookRef bookRef) {
    if (bookRef.Schema!.Navigation == null) {
      return <EpubChapterRef>[];
    }
    return getChaptersImpl(
        bookRef, bookRef.Schema!.Navigation!.NavMap!.Points!);
  }

  List<EpubChapterRef> getChaptersImpl(
      EpubBookRef bookRef, List<EpubNavigationPoint> navigationPoints) {
    final List<EpubChapterRef> result = <EpubChapterRef>[];
    for (EpubNavigationPoint navigationPoint in navigationPoints) {
      // A navigation point with no content source points nowhere, so it is
      // skipped rather than refused.
      final String? source = navigationPoint.Content?.Source;
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
    final String contentFileName = Uri.decodeFull(anchorCharIndex == -1
        ? contentSource
        : contentSource.substring(0, anchorCharIndex));
    final String? anchor = anchorCharIndex == -1
        ? null
        : contentSource.substring(anchorCharIndex + 1);

    if (!bookRef.Content!.Html!.containsKey(contentFileName)) {
      throw EpubUnresolvedReferenceException(
          'Incorrect EPUB manifest: item with href = "$contentFileName" is missing.');
    }

    final EpubChapterRef chapterRef = EpubChapterRef(bookRef.Content!.Html![contentFileName])
      ..ContentFileName = contentFileName
      ..Anchor = anchor
      ..Title = navigationPoint.NavigationLabels!.first.Text
      ..SubChapters =
          getChaptersImpl(bookRef, navigationPoint.ChildNavigationPoints!);
    _addSplitSiblings(bookRef, chapterRef, contentFileName);
    return chapterRef;
  }

  /// Some producers cut one source document into `_split_`-suffixed siblings.
  /// The navigation names only the first, so the chapter carries the rest of
  /// the family with it.
  void _addSplitSiblings(
      EpubBookRef bookRef, EpubChapterRef chapterRef, String contentFileName) {
    if (!chapterRef.ContentFileName!.contains('_split_')) {
      return;
    }
    final String fileNamePart = chapterRef.ContentFileName!.split('_split_')[0];
    for (String fileName in bookRef.Content!.Html!.keys) {
      if (fileName.contains(fileNamePart) && fileName != contentFileName) {
        chapterRef.otherTextContentFileRefs
            .add(bookRef.Content!.Html![fileName]!);
        chapterRef.OtherContentFileNames.add(fileName);
      }
    }
  }
}
