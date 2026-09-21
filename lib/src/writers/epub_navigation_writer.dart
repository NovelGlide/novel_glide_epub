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

      writeNavigationHead(builder, navigation.Head!);
      writeNavigationDocTitle(builder, navigation.DocTitle!);
      writeNavigationMap(builder, navigation.NavMap!);
    });

    return builder.buildDocument().toXmlString(pretty: false);
  }

  void writeNavigationDocTitle(
      XmlBuilder builder, EpubNavigationDocTitle title) {
    builder.element('docTitle', nest: () {
      title.Titles!.forEach(builder.text);
    });
  }

  void writeNavigationHead(XmlBuilder builder, EpubNavigationHead head) {
    builder.element('head', nest: () {
      for (EpubNavigationHeadMeta item in head.Metadata!) {
        builder.element('meta',
            attributes: <String, String>{'content': item.Content!, 'name': item.Name!});
      }
    });
  }

  void writeNavigationMap(XmlBuilder builder, EpubNavigationMap map) {
    builder.element('navMap', nest: () {
      for (EpubNavigationPoint item in map.Points!) {
        writeNavigationPoint(builder, item);
      }
    });
  }

  void writeNavigationPoint(XmlBuilder builder, EpubNavigationPoint point) {
    builder.element('navPoint', attributes: <String, String>{
      'id': point.Id!,
      'playOrder': point.PlayOrder!,
    }, nest: () {
      for (EpubNavigationLabel element in point.NavigationLabels!) {
        builder.element('navLabel', nest: () {
          builder.element('text', nest: () {
            builder.text(element.Text!);
          });
        });
      }
      builder.element('content', attributes: <String, String>{'src': point.Content!.Source!});
    });
  }
}
