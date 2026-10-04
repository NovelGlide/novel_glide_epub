import 'package:equatable/equatable.dart';

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
class EpubMetadata extends Equatable {
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
  List<Object?> get props => <Object?>[
        titles,
        creators,
        subjects,
        descriptions,
        publishers,
        contributors,
        dates,
        types,
        formats,
        identifiers,
        sources,
        languages,
        relations,
        coverages,
        rights,
        metaItems
      ];
}
