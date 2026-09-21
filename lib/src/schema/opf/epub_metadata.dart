import 'package:quiver/collection.dart' as collections;
import 'package:quiver/core.dart';

import 'epub_metadata_contributor.dart';
import 'epub_metadata_creator.dart';
import 'epub_metadata_date.dart';
import 'epub_metadata_identifier.dart';
import 'epub_metadata_meta.dart';

class EpubMetadata {
  List<String>? Titles;
  List<EpubMetadataCreator>? Creators;
  List<String>? Subjects;
  String? Description;
  List<String>? Publishers;
  List<EpubMetadataContributor>? Contributors;
  List<EpubMetadataDate>? Dates;
  List<String>? Types;
  List<String>? Formats;
  List<EpubMetadataIdentifier>? Identifiers;
  List<String>? Sources;
  List<String>? Languages;
  List<String>? Relations;
  List<String>? Coverages;
  List<String>? Rights;
  List<EpubMetadataMeta>? MetaItems;

  @override
  int get hashCode {
    final List<int> objects = <int>[
      ...Titles!.map((String title) => title.hashCode),
      ...Creators!.map((EpubMetadataCreator creator) => creator.hashCode),
      ...Subjects!.map((String subject) => subject.hashCode),
      ...Publishers!.map((String publisher) => publisher.hashCode),
      ...Contributors!.map((EpubMetadataContributor contributor) => contributor.hashCode),
      ...Dates!.map((EpubMetadataDate date) => date.hashCode),
      ...Types!.map((String type) => type.hashCode),
      ...Formats!.map((String format) => format.hashCode),
      ...Identifiers!.map((EpubMetadataIdentifier identifier) => identifier.hashCode),
      ...Sources!.map((String source) => source.hashCode),
      ...Languages!.map((String language) => language.hashCode),
      ...Relations!.map((String relation) => relation.hashCode),
      ...Coverages!.map((String coverage) => coverage.hashCode),
      ...Rights!.map((String right) => right.hashCode),
      ...MetaItems!.map((EpubMetadataMeta metaItem) => metaItem.hashCode),
      Description.hashCode
    ];

    return hashObjects(objects);
  }

  /// The fifteen Dublin Core lists are compared in three groups, one per
  /// question the group answers, so no single unit carries all of them.
  @override
  bool operator ==(Object other) =>
      other is EpubMetadata &&
      Description == other.Description &&
      collections.listsEqual(MetaItems, other.MetaItems) &&
      _attributionEqual(other) &&
      _classificationEqual(other) &&
      _provenanceEqual(other);

  /// Who made this and when — the elements that credit the work.
  bool _attributionEqual(EpubMetadata other) =>
      collections.listsEqual(Titles, other.Titles) &&
      collections.listsEqual(Creators, other.Creators) &&
      collections.listsEqual(Contributors, other.Contributors) &&
      collections.listsEqual(Publishers, other.Publishers) &&
      collections.listsEqual(Dates, other.Dates);

  /// What kind of thing this is — the elements a catalogue files it under.
  bool _classificationEqual(EpubMetadata other) =>
      collections.listsEqual(Subjects, other.Subjects) &&
      collections.listsEqual(Types, other.Types) &&
      collections.listsEqual(Formats, other.Formats) &&
      collections.listsEqual(Languages, other.Languages) &&
      collections.listsEqual(Coverages, other.Coverages);

  /// Where this came from and on what terms.
  bool _provenanceEqual(EpubMetadata other) =>
      collections.listsEqual(Identifiers, other.Identifiers) &&
      collections.listsEqual(Sources, other.Sources) &&
      collections.listsEqual(Relations, other.Relations) &&
      collections.listsEqual(Rights, other.Rights);
}
