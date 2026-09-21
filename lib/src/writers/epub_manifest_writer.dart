import 'package:xml/xml.dart';

import '../schema/opf/epub_manifest.dart';

class EpubManifestWriter {
  const EpubManifestWriter();

  void writeManifest(XmlBuilder builder, EpubManifest? manifest) {
    builder.element('manifest', nest: () {
      for (var item in manifest!.Items!) {
        builder.element('item', nest: () {
          builder
            ..attribute('id', item.Id!)
            ..attribute('href', item.Href!)
            ..attribute('media-type', item.MediaType!);
        });
      }
    });
  }
}
