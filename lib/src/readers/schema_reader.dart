import 'dart:async';

import 'package:archive/archive.dart';

import '../entities/epub_schema.dart';
import '../schema/opf/epub_manifest_item.dart';
import '../schema/opf/epub_package.dart';
import '../utils/container_index.dart';
import '../utils/zip_path_resolver.dart';
import 'navigation_reader.dart';
import 'package_reader.dart';
import 'root_file_path_reader.dart';

class SchemaReader {
  const SchemaReader();

  ZipPathResolver get _pathResolver => const ZipPathResolver();
  RootFilePathReader get _rootFilePathReader => const RootFilePathReader();
  PackageReader get _packageReader => const PackageReader();
  NavigationReader get _navigationReader => const NavigationReader();

  /// The schema of the book in [epubArchive].
  ///
  /// When [epubArchive] is a [ContainerIndex], the package document and
  /// every file its manifest lists are kept in it once the package is read,
  /// before the navigation document, one of them, is looked for.
  Future<EpubSchema> readSchema(Archive epubArchive) async {
    final String rootFilePath =
        (await _rootFilePathReader.getRootFilePath(epubArchive))!;
    final String contentDirectoryPath =
        _pathResolver.getDirectoryPath(rootFilePath);
    final EpubPackage package =
        await _packageReader.readPackage(epubArchive, rootFilePath);
    if (epubArchive is ContainerIndex) {
      epubArchive.keep(<String>{
        rootFilePath,
        for (final EpubManifestItem item in package.manifest.items)
          _pathResolver.combine(
              contentDirectoryPath, _pathResolver.decodeHref(item.href)),
      });
    }

    return EpubSchema(
      package: package,
      navigation: await _navigationReader.readNavigation(
          epubArchive, contentDirectoryPath, package),
      contentDirectoryPath: contentDirectoryPath,
    );
  }
}
