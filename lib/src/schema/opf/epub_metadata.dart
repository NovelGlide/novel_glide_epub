import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_metadata_contributor.dart';
import 'epub_metadata_creator.dart';
import 'epub_metadata_date.dart';
import 'epub_metadata_identifier.dart';
import 'epub_metadata_meta.dart';

/// The package `<metadata>`.
///
/// Every Dublin Core element may repeat, so each is a list, empty when the
/// book has none. `titles`, `identifiers` and `languages` are the ones OPF
/// requires; a book missing one still opens, with that list empty.
class EpubMetadata {
  const EpubMetadata({
    required this.titles,
    required this.identifiers,
    required this.languages,
    this.creators = const <EpubMetadataCreator>[],
    this.subjects = const <String>[],
    this.descriptions = const <String>[],
    this.publishers = const <String>[],
    this.contributors = const <EpubMetadataContributor>[],
    this.dates = const <EpubMetadataDate>[],
    this.types = const <String>[],
    this.formats = const <String>[],
    this.sources = const <String>[],
    this.relations = const <String>[],
    this.coverages = const <String>[],
    this.rights = const <String>[],
    this.metaItems = const <EpubMetadataMeta>[],
  });

  final List<String> titles;
  final List<EpubMetadataCreator> creators;
  final List<String> subjects;

  final List<String> descriptions;
  final List<String> publishers;
  final List<EpubMetadataContributor> contributors;
  final List<EpubMetadataDate> dates;
  final List<String> types;
  final List<String> formats;
  final List<EpubMetadataIdentifier> identifiers;
  final List<String> sources;
  final List<String> languages;
  final List<String> relations;
  final List<String> coverages;
  final List<String> rights;
  final List<EpubMetadataMeta> metaItems;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      ...titles.map((String title) => title.hashCode),
      ...creators.map((EpubMetadataCreator creator) => creator.hashCode),
      ...subjects.map((String subject) => subject.hashCode),
      ...publishers.map((String publisher) => publisher.hashCode),
      ...contributors
          .map((EpubMetadataContributor contributor) => contributor.hashCode),
      ...dates.map((EpubMetadataDate date) => date.hashCode),
      ...types.map((String type) => type.hashCode),
      ...formats.map((String format) => format.hashCode),
      ...identifiers
          .map((EpubMetadataIdentifier identifier) => identifier.hashCode),
      ...sources.map((String source) => source.hashCode),
      ...languages.map((String language) => language.hashCode),
      ...relations.map((String relation) => relation.hashCode),
      ...coverages.map((String coverage) => coverage.hashCode),
      ...rights.map((String right) => right.hashCode),
      ...metaItems.map((EpubMetadataMeta metaItem) => metaItem.hashCode),
      ...descriptions.map((String description) => description.hashCode),
    ];

    return hashObjects(objects);
  }

  /// The fifteen Dublin Core lists are compared in three groups, one per
  /// question the group answers, so no single unit carries all of them.
  @override
  bool operator ==(Object other) =>
      other is EpubMetadata &&
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
      collections.listsEqual(descriptions, other.descriptions) &&
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
