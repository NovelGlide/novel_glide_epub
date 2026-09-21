import 'package:xml/xml.dart';

import '../schema/opf/epub_spine.dart';
import '../schema/opf/epub_spine_item_ref.dart';

class EpubSpineWriter {
  const EpubSpineWriter();

  void writeSpine(XmlBuilder builder, EpubSpine spine) {
    builder.element('spine', attributes: <String, String>{'toc': spine.TableOfContents!},
        nest: () {
      for (EpubSpineItemRef spineitem in spine.Items!) {
        builder.element('itemref', attributes: <String, String>{
          'idref': spineitem.IdRef!,
          'linear': spineitem.IsLinear! ? 'yes' : 'no'
        });
      }
    });
  }
}
