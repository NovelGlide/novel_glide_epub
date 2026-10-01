import 'dart:typed_data';

import 'package:archive/archive.dart';

/// The entries of an opened book's ZIP container that opening it keeps, as
/// an [Archive] that finds any other entry when it is asked for by name.
///
/// [files] are the entries opening kept: `mimetype`, every `META-INF/`
/// entry, the package document and the manifest's files. Their locations are
/// all that is kept, never their bytes. [findFile] answers a kept name at
/// once and any other by reading the container's central directory once
/// more, record by record; an entry found that way is kept from then on,
/// apart from [files], so the next read of it is direct.
abstract class ContainerIndex extends Archive {
  /// Keeps, in [files], every entry named in [names], in one pass over the
  /// central directory.
  ///
  /// A name is matched as `package:archive` names entries, with each `\` read
  /// as a `/`. An entry whose name differs from one of [names] only in case
  /// is kept too, the first in the directory for each, so that a document
  /// looked up regardless of case is found among [files].
  void keep(Set<String> names);

  /// The bytes of the entry named [name], read as every read of an entry
  /// through the book is, and held to [maxBytes] as well when it is given;
  /// null when the container holds no such entry.
  Uint8List? read(String name, int? maxBytes);
}
