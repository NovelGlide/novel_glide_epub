class EpubNavigationLabel {
  String? Text;

  @override
  int get hashCode => Text.hashCode;

  @override
  bool operator ==(Object other) {
    if (other is! EpubNavigationLabel) {
      return false;
    }
    return Text == other.Text;
  }

  /// A label with no text renders as the empty string. `toString` is what
  /// error messages, debuggers and string interpolation reach for, so it
  /// answers for every state this object can be in rather than throwing on
  /// the one the NCX is allowed to leave empty.
  @override
  String toString() => Text ?? '';
}
