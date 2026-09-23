import 'package:quiver/core.dart';

import '../schema/navigation/epub_navigation.dart';
import '../schema/opf/epub_package.dart';

class EpubSchema {
  const EpubSchema({
    required this.package,
    required this.navigation,
    required this.contentDirectoryPath,
  });

  final EpubPackage package;
  final EpubNavigation navigation;

  /// The directory of the package document inside the archive, with no
  /// trailing slash; empty when the package document sits at the root.
  final String contentDirectoryPath;

  @override
  int get hashCode => hash3(
      package.hashCode, navigation.hashCode, contentDirectoryPath.hashCode);

  @override
  bool operator ==(Object other) {
    if (other is! EpubSchema) {
      return false;
    }

    return package == other.package &&
        navigation == other.navigation &&
        contentDirectoryPath == other.contentDirectoryPath;
  }
}
