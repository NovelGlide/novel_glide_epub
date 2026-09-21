import 'package:novel_glide_epub/src/schema/opf/epub_guide_reference.dart';
import 'package:xml/xml.dart';

import '../schema/opf/epub_guide.dart';

class EpubGuideWriter {
  const EpubGuideWriter();

  void writeGuide(XmlBuilder builder, EpubGuide? guide) {
    builder.element('guide', nest: () {
      for (EpubGuideReference guideItem in guide!.Items!) {
        builder.element('reference', attributes: <String, String>{
          'type': guideItem.Type!,
          'title': guideItem.Title!,
          'href': guideItem.Href!
        });
      }
    });
  }
}
