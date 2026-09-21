import 'dart:async';

import 'package:archive/archive.dart';
import 'package:novel_glide_epub/src/schema/navigation/epub_navigation.dart';
import 'package:novel_glide_epub/src/schema/opf/epub_package.dart';

import '../entities/epub_schema.dart';
import '../utils/zip_path_resolver.dart';
import 'navigation_reader.dart';
import 'package_reader.dart';
import 'root_file_path_reader.dart';

class SchemaReader {
  const SchemaReader({
    ZipPathResolver pathResolver = const ZipPathResolver(),
    RootFilePathReader rootFilePathReader = const RootFilePathReader(),
    PackageReader packageReader = const PackageReader(),
    NavigationReader navigationReader = const NavigationReader(),
  })  : _pathResolver = pathResolver,
        _rootFilePathReader = rootFilePathReader,
        _packageReader = packageReader,
        _navigationReader = navigationReader;

  final ZipPathResolver _pathResolver;
  final RootFilePathReader _rootFilePathReader;
  final PackageReader _packageReader;
  final NavigationReader _navigationReader;

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
