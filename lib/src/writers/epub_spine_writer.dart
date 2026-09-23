import 'package:xml/xml.dart';

import '../schema/opf/epub_spine.dart';
import '../schema/opf/epub_spine_item_ref.dart';

class EpubSpineWriter {
  const EpubSpineWriter();

  void writeSpine(XmlBuilder builder, EpubSpine spine) {
    final String? tableOfContents = spine.tableOfContents;
    builder.element('spine', attributes: <String, String>{
      if (tableOfContents != null) 'toc': tableOfContents,
    }, nest: () {
      for (EpubSpineItemRef spineitem in spine.items) {
        builder.element('itemref', attributes: <String, String>{
          'idref': spineitem.idRef,
          'linear': spineitem.isLinear ? 'yes' : 'no'
        });
      }
    });
  }
}
