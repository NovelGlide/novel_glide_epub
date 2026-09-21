import 'package:xml/xml.dart';

import '../schema/opf/epub_package.dart';
import '../schema/opf/epub_version.dart';
import 'epub_guide_writer.dart';
import 'epub_manifest_writer.dart';
import 'epub_metadata_writer.dart';
import 'epub_spine_writer.dart';

class EpubPackageWriter {
  const EpubPackageWriter();

  static const String _namespace = 'http://www.idpf.org/2007/opf';

  final EpubMetadataWriter _metadataWriter = const EpubMetadataWriter();
  final EpubManifestWriter _manifestWriter = const EpubManifestWriter();
  final EpubSpineWriter _spineWriter = const EpubSpineWriter();
  final EpubGuideWriter _guideWriter = const EpubGuideWriter();

  String writeContent(EpubPackage package) {
    var builder = XmlBuilder();
    builder.processing('xml', 'version="1.0"');

    builder.element('package', attributes: {
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
