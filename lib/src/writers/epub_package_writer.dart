import 'package:xml/xml.dart';

import '../schema/opf/epub_package.dart';
import '../schema/opf/epub_version.dart';
import 'epub_guide_writer.dart';
import 'epub_manifest_writer.dart';
import 'epub_metadata_writer.dart';
import 'epub_spine_writer.dart';

class EpubPackageWriter {
  const EpubPackageWriter({
    EpubMetadataWriter metadataWriter = const EpubMetadataWriter(),
    EpubManifestWriter manifestWriter = const EpubManifestWriter(),
    EpubSpineWriter spineWriter = const EpubSpineWriter(),
    EpubGuideWriter guideWriter = const EpubGuideWriter(),
  })  : _metadataWriter = metadataWriter,
        _manifestWriter = manifestWriter,
        _spineWriter = spineWriter,
        _guideWriter = guideWriter;

  static const String _namespace = 'http://www.idpf.org/2007/opf';

  final EpubMetadataWriter _metadataWriter;
  final EpubManifestWriter _manifestWriter;
  final EpubSpineWriter _spineWriter;
  final EpubGuideWriter _guideWriter;

  String writeContent(EpubPackage package) {
    final XmlBuilder builder = XmlBuilder();
    builder.processing('xml', 'version="1.0"');

    builder.element('package', attributes: <String, String>{
      'version': package.Version == EpubVersion.Epub2 ? '2.0' : '3.0',
      'unique-identifier': 'etextno',
    }, nest: () {
      builder.namespace(_namespace);

      _metadataWriter.writeMetadata(builder, package.Metadata, package.Version);
      _manifestWriter.writeManifest(builder, package.Manifest);
      _spineWriter.writeSpine(builder, package.Spine!);
      _guideWriter.writeGuide(builder, package.Guide);
    });

    return builder.buildDocument().toXmlString(pretty: false);
  }
}
