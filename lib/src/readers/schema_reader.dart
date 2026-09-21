import 'dart:async';

import 'package:archive/archive.dart';

import '../entities/epub_schema.dart';
import '../schema/navigation/epub_navigation.dart';
import '../schema/opf/epub_package.dart';
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

  Future<EpubSchema> readSchema(Archive epubArchive) async {
    final EpubSchema result = EpubSchema();

    final String rootFilePath =
        (await _rootFilePathReader.getRootFilePath(epubArchive))!;
    final String contentDirectoryPath = _pathResolver.getDirectoryPath(rootFilePath);
    result.ContentDirectoryPath = contentDirectoryPath;

    final EpubPackage package = await _packageReader.readPackage(epubArchive, rootFilePath);
    result.Package = package;

    final EpubNavigation navigation = await _navigationReader.readNavigation(
        epubArchive, contentDirectoryPath, package);
    result.Navigation = navigation;

    return result;
  }
}
