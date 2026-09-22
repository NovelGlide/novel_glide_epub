import 'package:xml/xml.dart';

import '../schema/opf/epub_guide.dart';
import '../schema/opf/epub_guide_reference.dart';

class EpubGuideWriter {
  const EpubGuideWriter();

  void writeGuide(XmlBuilder builder, EpubGuide? guide) {
    builder.element('guide', nest: () {
      for (EpubGuideReference guideItem in guide!.items!) {
        builder.element('reference', attributes: <String, String>{
          'type': guideItem.type!,
          'title': guideItem.title!,
          'href': guideItem.href!
        });
      }
    });
  }
}
