import 'package:xml/xml.dart';

import '../schema/navigation/epub_navigation.dart';
import '../schema/navigation/epub_navigation_doc_title.dart';
import '../schema/navigation/epub_navigation_head.dart';
import '../schema/navigation/epub_navigation_head_meta.dart';
import '../schema/navigation/epub_navigation_label.dart';
import '../schema/navigation/epub_navigation_map.dart';
import '../schema/navigation/epub_navigation_point.dart';

class EpubNavigationWriter {
  const EpubNavigationWriter();

  static const String _namespace = 'http://www.daisy.org/z3986/2005/ncx/';

  String writeNavigation(EpubNavigation navigation) {
    final XmlBuilder builder = XmlBuilder();
    builder.processing('xml', 'version="1.0"');

    builder.element('ncx', attributes: <String, String>{
      'version': '2005-1',
      'lang': 'en',
    }, nest: () {
      builder.namespace(_namespace);

      writeNavigationHead(builder, navigation.head);
      writeNavigationDocTitle(builder, navigation.docTitle);
      writeNavigationMap(builder, navigation.navMap);
    });

    return builder.buildDocument().toXmlString(pretty: false);
  }

  void writeNavigationDocTitle(
      XmlBuilder builder, EpubNavigationDocTitle title) {
    builder.element('docTitle', nest: () {
      title.titles.forEach(builder.text);
    });
  }

  void writeNavigationHead(XmlBuilder builder, EpubNavigationHead head) {
    builder.element('head', nest: () {
      for (EpubNavigationHeadMeta item in head.metadata) {
        builder.element('meta', attributes: <String, String>{
          'content': item.content,
          'name': item.name
        });
      }
    });
  }

  /// An EPUB 3 heading entry links nowhere, and an NCX `navPoint` must carry
  /// a `content` link, so such an entry has no NCX form and is left out.
  void writeNavigationMap(XmlBuilder builder, EpubNavigationMap map) {
    builder.element('navMap', nest: () {
      for (EpubNavigationPoint item in map.points) {
        final String? source = item.content.source;
        if (source != null) {
          writeNavigationPoint(builder, item, source);
        }
      }
    });
  }

  /// Writes [point] linking to [source], its content's source.
  void writeNavigationPoint(
      XmlBuilder builder, EpubNavigationPoint point, String source) {
    builder.element('navPoint', attributes: <String, String>{
      'id': point.id,
      'playOrder': point.playOrder,
    }, nest: () {
      for (EpubNavigationLabel element in point.navigationLabels) {
        builder.element('navLabel', nest: () {
          builder.element('text', nest: () {
            builder.text(element.text);
          });
        });
      }
      builder.element('content', attributes: <String, String>{'src': source});
    });
  }
}
