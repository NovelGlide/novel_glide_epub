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
      XmlBuilder builder, EpubMetadata? meta, EpubVersion? version) {
    builder.element('metadata',
        namespaces: <String, String?>{_opfNamespace: 'opf', _dcNamespace: 'dc'},
        nest: () {
      _writeAttribution(builder, meta!);
      _writeClassification(builder, meta);
      _writeProvenance(builder, meta);
      _writeMetaItems(builder, meta.metaItems, version);

      if (meta.description != null) {
        builder.element('description',
            namespace: _dcNamespace, nest: meta.description);
      }
    });
  }

  /// Who made this and when — the elements that credit the work.
  void _writeAttribution(XmlBuilder builder, EpubMetadata meta) {
    meta.titles?.forEach((String item) =>
        builder.element('title', nest: item, namespace: _dcNamespace));
    meta.creators?.forEach((EpubMetadataCreator item) =>
        builder.element('creator', namespace: _dcNamespace, nest: () {
          _writeAgentAttributes(builder, role: item.role, fileAs: item.fileAs);
          builder.text(item.creator!);
        }));
    meta.contributors?.forEach((EpubMetadataContributor item) =>
        builder.element('contributor', namespace: _dcNamespace, nest: () {
          _writeAgentAttributes(builder, role: item.role, fileAs: item.fileAs);
          builder.text(item.contributor!);
        }));
    meta.publishers?.forEach((String item) =>
        builder.element('publisher', namespace: _dcNamespace, nest: item));
    meta.dates?.forEach((EpubMetadataDate date) =>
        builder.element('date', namespace: _dcNamespace, nest: () {
          if (date.event != null) {
            builder.attribute('event', date.event!, namespace: _opfNamespace);
          }
          builder.text(date.date!);
        }));
  }

  /// The two optional attributes a creator and a contributor share; they are
  /// the same person-shaped element under two names.
  void _writeAgentAttributes(XmlBuilder builder,
      {required String? role, required String? fileAs}) {
    if (role != null) {
      builder.attribute('role', role, namespace: _opfNamespace);
    }
    if (fileAs != null) {
      builder.attribute('file-as', fileAs, namespace: _opfNamespace);
    }
  }

  /// What kind of thing this is — the elements a catalogue files it under.
  void _writeClassification(XmlBuilder builder, EpubMetadata meta) {
    meta.subjects?.forEach((String item) =>
        builder.element('subject', namespace: _dcNamespace, nest: item));
    meta.types?.forEach((String type) =>
        builder.element('type', namespace: _dcNamespace, nest: type));
    meta.formats?.forEach((String format) =>
        builder.element('format', namespace: _dcNamespace, nest: format));
    meta.languages?.forEach((String item) =>
        builder.element('language', namespace: _dcNamespace, nest: item));
    meta.coverages?.forEach((String item) =>
        builder.element('coverage', namespace: _dcNamespace, nest: item));
  }

  /// Where this came from and on what terms.
  void _writeProvenance(XmlBuilder builder, EpubMetadata meta) {
    meta.identifiers?.forEach((EpubMetadataIdentifier id) =>
        builder.element('identifier', namespace: _dcNamespace, nest: () {
          if (id.id != null) {
            builder.attribute('id', id.id!);
          }
          if (id.scheme != null) {
            builder.attribute('scheme', id.scheme!, namespace: _opfNamespace);
          }
          builder.text(id.identifier!);
        }));
    meta.sources?.forEach((String item) =>
        builder.element('source', namespace: _dcNamespace, nest: item));
    meta.relations?.forEach((String item) =>
        builder.element('relation', namespace: _dcNamespace, nest: item));
    meta.rights?.forEach((String item) =>
        builder.element('rights', namespace: _dcNamespace, nest: item));
  }

  /// `<meta>` is the one metadata element whose shape changed between EPUB2
  /// and EPUB3, so the version picks which set of attributes is written; a
  /// version this writer does not know emits the element with none of them.
  void _writeMetaItems(XmlBuilder builder, List<EpubMetadataMeta>? metaItems,
      EpubVersion? version) {
    metaItems?.forEach(
        (EpubMetadataMeta metaitem) => builder.element('meta', nest: () {
              if (version == EpubVersion.epub2) {
                _writeEpub2MetaAttributes(builder, metaitem);
              } else if (version == EpubVersion.epub3) {
                _writeEpub3MetaAttributes(builder, metaitem);
              }
            }));
  }

  /// EPUB2 `<meta>`: a name/content pair, which is how a book of that vintage
  /// points at its cover.
  void _writeEpub2MetaAttributes(XmlBuilder builder, EpubMetadataMeta item) {
    if (item.name != null) {
      builder.attribute('name', item.name!);
    }
    if (item.content != null) {
      builder.attribute('content', item.content!);
    }
  }

  /// EPUB3 `<meta>`: a property refining another element, identified by id and
  /// read against a scheme.
  void _writeEpub3MetaAttributes(XmlBuilder builder, EpubMetadataMeta item) {
    if (item.id != null) {
      builder.attribute('id', item.id!);
    }
    if (item.refines != null) {
      builder.attribute('refines', item.refines!);
    }
    if (item.property != null) {
      builder.attribute('property', item.property!);
    }
    if (item.scheme != null) {
      builder.attribute('scheme', item.scheme!);
    }
  }
}
