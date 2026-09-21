/// Resolves a path inside the EPUB's ZIP container.
///
/// Every path an EPUB names is relative to the document that names it, so
/// reading one means joining it onto the directory of the other; this is the
/// one place that join happens.
class ZipPathResolver {
  const ZipPathResolver();

  String getDirectoryPath(String filePath) {
    final int lastSlashIndex = filePath.lastIndexOf('/');
    if (lastSlashIndex == -1) {
      return '';
    } else {
      return filePath.substring(0, lastSlashIndex);
    }
  }

  String? combine(String? directory, String? fileName) {
    var path;
    if (directory == null || directory == '') {
      path = fileName;
    } else {
      path = directory + '/' + fileName!;
    }
    return Uri.parse(path).normalizePath().path;
  }
}
