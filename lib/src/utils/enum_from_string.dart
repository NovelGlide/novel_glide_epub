import 'package:collection/collection.dart' show IterableExtension;

/// Looks an enum value up by the name it carries in the EPUB, case-insensitively.
///
/// A name no value answers to yields null: an EPUB is free to carry a value
/// from a later version of the format than this parser knows, and that is not
/// a reason to refuse the book.
class EnumFromString<T> {
  EnumFromString(this.enumValues);

  List<T> enumValues;

  T? get(String value) {
    final String target = '$T.$value'.toUpperCase();
    return enumValues
        .firstWhereOrNull((T f) => f.toString().toUpperCase() == target);
  }
}
