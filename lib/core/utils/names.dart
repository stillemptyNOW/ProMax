// #***! имя одной строкой
String displayName(Object? first, Object? last, {String fallback = ''}) {
  final f = first?.toString().trim() ?? '';
  final l = last?.toString().trim() ?? '';
  final full = [f, l].where((s) => s.isNotEmpty).join(' ');
  return full.isEmpty ? fallback : full;
}

({String firstName, String lastName}) contactNameForSave({
  required String firstName,
  required String lastName,
  required String profileFirstName,
  required String profileLastName,
}) {
  final first = firstName.trim();
  final last = lastName.trim();
  if (first.isEmpty && last.isEmpty) {
    return (
      firstName: profileFirstName.trim(),
      lastName: profileLastName.trim(),
    );
  }
  return (firstName: first, lastName: last);
}
