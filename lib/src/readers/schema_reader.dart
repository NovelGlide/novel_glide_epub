import 'dart:async';

import 'package:archive/archive.dart';

import '../entities/epub_schema.dart';
import '../utils/zip_path_resolver.dart';
import 'navigation_reader.dart';
import 'package_reader.dart';
import 'root_file_path_reader.dart';

class SchemaReader {
  const SchemaReader();

  final ZipPathResolver _pathResolver = const ZipPathResolver();
  final RootFilePathReader _rootFilePathReader = const RootFilePathReader();
  final PackageReader _packageReader = const PackageReader();
  final NavigationReader _navigationReader = const NavigationReader();

  Future<EpubSchema> readSchema(Archive epubArchive) async {
    var result = EpubSchema();

    var rootFilePath =
        (await _rootFilePathReader.getRootFilePath(epubArchive))!;
    var contentDirectoryPath = _pathResolver.getDirectoryPath(rootFilePath);
    result.ContentDirectoryPath = contentDirectoryPath;

    var package = await _packageReader.readPackage(epubArchive, rootFilePath);
    result.Package = package;

    var navigation = await _navigationReader.readNavigation(
        epubArchive, contentDirectoryPath, package);
    result.Navigation = navigation;

    return result;
  }
}
