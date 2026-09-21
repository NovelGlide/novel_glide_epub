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
    var result = <EpubChapterRef>[];
    for (var navigationPoint in navigationPoints) {
      // A navigation point with no content source points nowhere, so it is
      // skipped rather than refused.
      var source = navigationPoint.Content?.Source;
      if (source == null) {
        continue;
      }
      result.add(_readChapterRef(bookRef, navigationPoint, source));
    }
    return result;
  }

  EpubChapterRef _readChapterRef(EpubBookRef bookRef,
      EpubNavigationPoint navigationPoint, String contentSource) {
    var anchorCharIndex = contentSource.indexOf('#');
    var contentFileName = Uri.decodeFull(anchorCharIndex == -1
        ? contentSource
        : contentSource.substring(0, anchorCharIndex));
    var anchor = anchorCharIndex == -1
        ? null
        : contentSource.substring(anchorCharIndex + 1);

    if (!bookRef.Content!.Html!.containsKey(contentFileName)) {
      throw EpubUnresolvedReferenceException(
          'Incorrect EPUB manifest: item with href = "$contentFileName" is missing.');
    }

    var chapterRef = EpubChapterRef(bookRef.Content!.Html![contentFileName])
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
    var fileNamePart = chapterRef.ContentFileName!.split('_split_')[0];
    for (var fileName in bookRef.Content!.Html!.keys) {
      if (fileName.contains(fileNamePart) && fileName != contentFileName) {
        chapterRef.otherTextContentFileRefs
            .add(bookRef.Content!.Html![fileName]!);
        chapterRef.OtherContentFileNames.add(fileName);
      }
    }
  }
}
