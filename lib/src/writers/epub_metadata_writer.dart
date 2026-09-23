import 'package:xml/xml.dart';

import '../schema/opf/epub_metadata.dart';
import '../schema/opf/epub_metadata_contributor.dart';
import '../schema/opf/epub_metadata_creator.dart';
import '../schema/opf/epub_metadata_date.dart';
import '../schema/opf/epub_metadata_identifier.dart';
import '../schema/opf/epub_metadata_meta.dart';
import '../schema/opf/epub_version.dart';

class EpubMetadataWriter {
  const EpubMetadataWriter();

  static const String _dcNamespace = 'http://purl.org/dc/elements/1.1/';
  static const String _opfNamespace = 'http://www.idpf.org/2007/opf';

  /// Writes the `<metadata>` element.
  ///
  /// The fifteen Dublin Core lists are written in three groups, one per
  /// question the group answers — the same decomposition `EpubMetadata.==`
  /// uses to compare them. Regrouping means the elements come out in a
  /// different order than the entity declares them in; OPF gives
  /// `<metadata>` children no significant order, and `PackageReader` dispatches
  /// on element name, so the order is free to follow the meaning.
  void writeMetadata(
      XmlBuilder builder, EpubMetadata meta, EpubVersion version) {
    builder.element('metadata',
        namespaces: <String, String?>{_opfNamespace: 'opf', _dcNamespace: 'dc'},
        nest: () {
      _writeAttribution(builder, meta);
      _writeClassification(builder, meta);
      _writeProvenance(builder, meta);
      _writeMetaItems(builder, meta.metaItems, version);
    });
  }

  /// Who made this and when — the elements that credit the work.
  void _writeAttribution(XmlBuilder builder, EpubMetadata meta) {
    _writeTexts(builder, 'title', meta.titles);
    for (final EpubMetadataCreator item in meta.creators) {
      builder.element('creator', namespace: _dcNamespace, nest: () {
        _writeAgentAttributes(builder, role: item.role, fileAs: item.fileAs);
        builder.text(item.creator);
      });
    }
    for (final EpubMetadataContributor item in meta.contributors) {
      builder.element('contributor', namespace: _dcNamespace, nest: () {
        _writeAgentAttributes(builder, role: item.role, fileAs: item.fileAs);
        builder.text(item.contributor);
      });
    }
    _writeTexts(builder, 'publisher', meta.publishers);
    for (final EpubMetadataDate date in meta.dates) {
      builder.element('date', namespace: _dcNamespace, nest: () {
        _writeOptionalAttribute(builder, 'event', date.event,
            namespace: _opfNamespace);
        builder.text(date.date);
      });
    }
  }

  /// The two optional attributes a creator and a contributor share; they are
  /// the same person-shaped element under two names.
  void _writeAgentAttributes(XmlBuilder builder,
      {required String? role, required String? fileAs}) {
    _writeOptionalAttribute(builder, 'role', role, namespace: _opfNamespace);
    _writeOptionalAttribute(builder, 'file-as', fileAs,
        namespace: _opfNamespace);
  }

  /// What kind of thing this is — the elements a catalogue files it under.
  void _writeClassification(XmlBuilder builder, EpubMetadata meta) {
    _writeTexts(builder, 'subject', meta.subjects);
    _writeTexts(builder, 'description', meta.descriptions);
    _writeTexts(builder, 'type', meta.types);
    _writeTexts(builder, 'format', meta.formats);
    _writeTexts(builder, 'language', meta.languages);
    _writeTexts(builder, 'coverage', meta.coverages);
  }

  /// Where this came from and on what terms.
  void _writeProvenance(XmlBuilder builder, EpubMetadata meta) {
    for (final EpubMetadataIdentifier id in meta.identifiers) {
      builder.element('identifier', namespace: _dcNamespace, nest: () {
        _writeOptionalAttribute(builder, 'id', id.id);
        _writeOptionalAttribute(builder, 'scheme', id.scheme,
            namespace: _opfNamespace);
        builder.text(id.identifier);
      });
    }
    _writeTexts(builder, 'source', meta.sources);
    _writeTexts(builder, 'relation', meta.relations);
    _writeTexts(builder, 'rights', meta.rights);
  }

  /// One Dublin Core element per entry of [texts], each holding its text.
  void _writeTexts(XmlBuilder builder, String element, List<String> texts) {
    for (final String text in texts) {
      builder.element(element, namespace: _dcNamespace, nest: text);
    }
  }

  /// `<meta>` is the one metadata element whose shape changed between EPUB2
  /// and EPUB3, so the version picks which set of attributes is written.
  void _writeMetaItems(XmlBuilder builder, List<EpubMetadataMeta> metaItems,
      EpubVersion version) {
    for (final EpubMetadataMeta metaItem in metaItems) {
      builder.element('meta', nest: () {
        switch (version) {
          case EpubVersion.epub2:
            _writeEpub2MetaAttributes(builder, metaItem);
          case EpubVersion.epub3:
            _writeEpub3MetaAttributes(builder, metaItem);
        }
      });
    }
  }

  /// EPUB2 `<meta>`: a name/content pair, which is how a book of that vintage
  /// points at its cover.
  void _writeEpub2MetaAttributes(XmlBuilder builder, EpubMetadataMeta item) {
    _writeOptionalAttribute(builder, 'name', item.name);
    builder.attribute('content', item.content);
  }

  /// EPUB3 `<meta>`: a property refining another element, identified by id and
  /// read against a scheme.
  void _writeEpub3MetaAttributes(XmlBuilder builder, EpubMetadataMeta item) {
    _writeOptionalAttribute(builder, 'id', item.id);
    _writeOptionalAttribute(builder, 'refines', item.refines);
    _writeOptionalAttribute(builder, 'property', item.property);
    _writeOptionalAttribute(builder, 'scheme', item.scheme);
  }

  /// An attribute the element carries only when the book gave it a value.
  void _writeOptionalAttribute(XmlBuilder builder, String name, String? value,
      {String? namespace}) {
    if (value != null) {
      builder.attribute(name, value, namespace: namespace);
    }
  }
}
