import 'package:xml/xml.dart';

/// Reads an EPUB element's attributes by local name, ignoring case and
/// namespace prefix.
///
/// Real books write `opf:role` as often as `role`, and `playorder` as often
/// as `playOrder`; a lookup that minded either would lose the value.
class XmlAttributeReader {
  const XmlAttributeReader();

  /// The value of the attribute on [element] whose lower-cased local name is
  /// [localName], or null when there is none. Of two that share the name
  /// under different prefixes, the later wins.
  String? read(XmlElement element, String localName) =>
      readAll(element)[localName];

  /// Every attribute on [element], keyed by lower-cased local name; a later
  /// attribute replaces an earlier one with the same key.
  Map<String, String> readAll(XmlElement element) => <String, String>{
        for (final XmlAttribute attribute in element.attributes)
          attribute.name.local.toLowerCase(): attribute.value,
      };
}
