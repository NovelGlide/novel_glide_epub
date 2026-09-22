import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_metadata_contributor.dart';
import 'epub_metadata_creator.dart';
import 'epub_metadata_date.dart';
import 'epub_metadata_identifier.dart';
import 'epub_metadata_meta.dart';

class EpubMetadata {
  List<String>? titles;
  List<EpubMetadataCreator>? creators;
  List<String>? subjects;
  String? description;
  List<String>? publishers;
  List<EpubMetadataContributor>? contributors;
  List<EpubMetadataDate>? dates;
  List<String>? types;
  List<String>? formats;
  List<EpubMetadataIdentifier>? identifiers;
  List<String>? sources;
  List<String>? languages;
  List<String>? relations;
  List<String>? coverages;
  List<String>? rights;
  List<EpubMetadataMeta>? metaItems;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      ...titles!.map((String title) => title.hashCode),
      ...creators!.map((EpubMetadataCreator creator) => creator.hashCode),
      ...subjects!.map((String subject) => subject.hashCode),
      ...publishers!.map((String publisher) => publisher.hashCode),
      ...contributors!
          .map((EpubMetadataContributor contributor) => contributor.hashCode),
      ...dates!.map((EpubMetadataDate date) => date.hashCode),
      ...types!.map((String type) => type.hashCode),
      ...formats!.map((String format) => format.hashCode),
      ...identifiers!
          .map((EpubMetadataIdentifier identifier) => identifier.hashCode),
      ...sources!.map((String source) => source.hashCode),
      ...languages!.map((String language) => language.hashCode),
      ...relations!.map((String relation) => relation.hashCode),
      ...coverages!.map((String coverage) => coverage.hashCode),
      ...rights!.map((String right) => right.hashCode),
      ...metaItems!.map((EpubMetadataMeta metaItem) => metaItem.hashCode),
      description.hashCode
    ];

    return hashObjects(objects);
  }

  /// The fifteen Dublin Core lists are compared in three groups, one per
  /// question the group answers, so no single unit carries all of them.
  @override
  bool operator ==(Object other) =>
      other is EpubMetadata &&
      description == other.description &&
      collections.listsEqual(metaItems, other.metaItems) &&
      _attributionEqual(other) &&
      _classificationEqual(other) &&
      _provenanceEqual(other);

  /// Who made this and when — the elements that credit the work.
  bool _attributionEqual(EpubMetadata other) =>
      collections.listsEqual(titles, other.titles) &&
      collections.listsEqual(creators, other.creators) &&
      collections.listsEqual(contributors, other.contributors) &&
      collections.listsEqual(publishers, other.publishers) &&
      collections.listsEqual(dates, other.dates);

  /// What kind of thing this is — the elements a catalogue files it under.
  bool _classificationEqual(EpubMetadata other) =>
      collections.listsEqual(subjects, other.subjects) &&
      collections.listsEqual(types, other.types) &&
      collections.listsEqual(formats, other.formats) &&
      collections.listsEqual(languages, other.languages) &&
      collections.listsEqual(coverages, other.coverages);

  /// Where this came from and on what terms.
  bool _provenanceEqual(EpubMetadata other) =>
      collections.listsEqual(identifiers, other.identifiers) &&
      collections.listsEqual(sources, other.sources) &&
      collections.listsEqual(relations, other.relations) &&
      collections.listsEqual(rights, other.rights);
}
