import 'package:xml/xml.dart';

import '../schema/opf/epub_guide.dart';
import '../schema/opf/epub_package.dart';
import '../schema/opf/epub_version.dart';
import 'epub_guide_writer.dart';
import 'epub_manifest_writer.dart';
import 'epub_metadata_writer.dart';
import 'epub_spine_writer.dart';

class EpubPackageWriter {
  const EpubPackageWriter();

  static const String _namespace = 'http://www.idpf.org/2007/opf';

  EpubMetadataWriter get _metadataWriter => const EpubMetadataWriter();
  EpubManifestWriter get _manifestWriter => const EpubManifestWriter();
  EpubSpineWriter get _spineWriter => const EpubSpineWriter();
  EpubGuideWriter get _guideWriter => const EpubGuideWriter();

  String writeContent(EpubPackage package) {
    final XmlBuilder builder = XmlBuilder();
    builder.processing('xml', 'version="1.0"');

    builder.element('package', attributes: <String, String>{
      'version': package.version == EpubVersion.epub2 ? '2.0' : '3.0',
      'unique-identifier': 'etextno',
    }, nest: () {
      builder.namespace(_namespace);

      _metadataWriter.writeMetadata(builder, package.metadata, package.version);
      _manifestWriter.writeManifest(builder, package.manifest);
      _spineWriter.writeSpine(builder, package.spine);
      final EpubGuide? guide = package.guide;
      if (guide != null) {
        _guideWriter.writeGuide(builder, guide);
      }
    });

    return builder.buildDocument().toXmlString(pretty: false);
  }
}
