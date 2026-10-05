import 'package:equatable/equatable.dart';

import '../schema/navigation/epub_navigation.dart';
import '../schema/opf/epub_package.dart';

class EpubSchema extends Equatable {
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
  List<Object?> get props =>
      <Object?>[package, navigation, contentDirectoryPath];
}
