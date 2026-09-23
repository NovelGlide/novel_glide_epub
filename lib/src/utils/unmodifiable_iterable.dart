/// Freezes the collections a reader hands to an entity.
///
/// An entity is data that stays as the book wrote it once built, and it
/// hashes its lists by element: a list that could still grow would change
/// the entity's hash code after it was put in a set or used as a map key.
extension UnmodifiableIterable<T> on Iterable<T> {
  /// The elements, in order, in a list that cannot be added to or changed.
  List<T> toUnmodifiableList() => List<T>.unmodifiable(this);
}
