import 'package:xml/xml.dart';

import '../schema/opf/epub_metadata.dart';
import '../schema/opf/epub_metadata_meta.dart';
import '../schema/opf/epub_version.dart';

class EpubMetadataWriter {
  const EpubMetadataWriter();

  static const _dc_namespace = 'http://purl.org/dc/elements/1.1/';
  static const _opf_namespace = 'http://www.idpf.org/2007/opf';

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
        namespaces: {_opf_namespace: 'opf', _dc_namespace: 'dc'}, nest: () {
      _writeAttribution(builder, meta!);
      _writeClassification(builder, meta);
      _writeProvenance(builder, meta);
      _writeMetaItems(builder, meta.MetaItems, version);

      if (meta.Description != null) {
        builder.element('description',
            namespace: _dc_namespace, nest: meta.Description);
      }
    });
  }

  /// Who made this and when — the elements that credit the work.
  void _writeAttribution(XmlBuilder builder, EpubMetadata meta) {
    meta.Titles?.forEach((item) =>
        builder.element('title', nest: item, namespace: _dc_namespace));
    meta.Creators?.forEach((item) =>
        builder.element('creator', namespace: _dc_namespace, nest: () {
          _writeAgentAttributes(builder, role: item.Role, fileAs: item.FileAs);
          builder.text(item.Creator!);
        }));
    meta.Contributors?.forEach((item) =>
        builder.element('contributor', namespace: _dc_namespace, nest: () {
          _writeAgentAttributes(builder, role: item.Role, fileAs: item.FileAs);
          builder.text(item.Contributor!);
        }));
    meta.Publishers?.forEach((item) =>
        builder.element('publisher', namespace: _dc_namespace, nest: item));
    meta.Dates?.forEach((date) =>
        builder.element('date', namespace: _dc_namespace, nest: () {
          if (date.Event != null) {
            builder.attribute('event', date.Event!, namespace: _opf_namespace);
          }
          builder.text(date.Date!);
        }));
  }

  /// The two optional attributes a creator and a contributor share; they are
  /// the same person-shaped element under two names.
  void _writeAgentAttributes(XmlBuilder builder,
      {required String? role, required String? fileAs}) {
    if (role != null) {
      builder.attribute('role', role, namespace: _opf_namespace);
    }
    if (fileAs != null) {
      builder.attribute('file-as', fileAs, namespace: _opf_namespace);
    }
  }

  /// What kind of thing this is — the elements a catalogue files it under.
  void _writeClassification(XmlBuilder builder, EpubMetadata meta) {
    meta.Subjects?.forEach((item) =>
        builder.element('subject', namespace: _dc_namespace, nest: item));
    meta.Types?.forEach((type) =>
        builder.element('type', namespace: _dc_namespace, nest: type));
    meta.Formats?.forEach((format) =>
        builder.element('format', namespace: _dc_namespace, nest: format));
    meta.Languages?.forEach((item) =>
        builder.element('language', namespace: _dc_namespace, nest: item));
    meta.Coverages?.forEach((item) =>
        builder.element('coverage', namespace: _dc_namespace, nest: item));
  }

  /// Where this came from and on what terms.
  void _writeProvenance(XmlBuilder builder, EpubMetadata meta) {
    meta.Identifiers?.forEach((id) =>
        builder.element('identifier', namespace: _dc_namespace, nest: () {
          if (id.Id != null) builder.attribute('id', id.Id!);
          if (id.Scheme != null) {
            builder.attribute('scheme', id.Scheme!, namespace: _opf_namespace);
          }
          builder.text(id.Identifier!);
        }));
    meta.Sources?.forEach((item) =>
        builder.element('source', namespace: _dc_namespace, nest: item));
    meta.Relations?.forEach((item) =>
        builder.element('relation', namespace: _dc_namespace, nest: item));
    meta.Rights?.forEach((item) =>
        builder.element('rights', namespace: _dc_namespace, nest: item));
  }

  /// `<meta>` is the one metadata element whose shape changed between EPUB2
  /// and EPUB3, so the version picks which set of attributes is written; a
  /// version this writer does not know emits the element with none of them.
  void _writeMetaItems(XmlBuilder builder, List<EpubMetadataMeta>? metaItems,
      EpubVersion? version) {
    metaItems?.forEach((metaitem) => builder.element('meta', nest: () {
          if (version == EpubVersion.Epub2) {
            _writeEpub2MetaAttributes(builder, metaitem);
          } else if (version == EpubVersion.Epub3) {
            _writeEpub3MetaAttributes(builder, metaitem);
          }
        }));
  }

  /// EPUB2 `<meta>`: a name/content pair, which is how a book of that vintage
  /// points at its cover.
  void _writeEpub2MetaAttributes(XmlBuilder builder, EpubMetadataMeta item) {
    if (item.Name != null) {
      builder.attribute('name', item.Name!);
    }
    if (item.Content != null) {
      builder.attribute('content', item.Content!);
    }
  }

  /// EPUB3 `<meta>`: a property refining another element, identified by id and
  /// read against a scheme.
  void _writeEpub3MetaAttributes(XmlBuilder builder, EpubMetadataMeta item) {
    if (item.Id != null) {
      builder.attribute('id', item.Id!);
    }
    if (item.Refines != null) {
      builder.attribute('refines', item.Refines!);
    }
    if (item.Property != null) {
      builder.attribute('property', item.Property!);
    }
    if (item.Scheme != null) {
      builder.attribute('scheme', item.Scheme!);
    }
  }
}
