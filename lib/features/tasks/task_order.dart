/// How a list of task names is ordered for a person to read.
///
/// Alphabetical, because a list someone scans for a name should be where
/// the name would be. Case is ignored — "piano" and "Piano" are the same
/// word to a reader — and digits compare as numbers, so "Test 9" comes
/// before "Test 10" rather than after it, which is the one place plain
/// string order reliably surprises people.
int compareTaskNames(String a, String b) {
  final result = _natural(a, b);
  // Identical but for case: fall back to the raw strings so the order is
  // total and the sort is stable in practice as well as in theory.
  return result != 0 ? result : a.compareTo(b);
}

int _natural(String a, String b) {
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i);
    final cb = b.codeUnitAt(j);
    final aDigit = _isDigit(ca);
    final bDigit = _isDigit(cb);

    if (aDigit && bDigit) {
      // Whole runs of digits, compared as numbers. Leading zeros do not
      // change the value, so "Task 007" and "Task 7" tie here and the
      // caller's fallback puts them in a fixed order.
      final startA = i, startB = j;
      while (i < a.length && _isDigit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && _isDigit(b.codeUnitAt(j))) {
        j++;
      }
      final numA = a.substring(startA, i);
      final numB = b.substring(startB, j);
      final trimmedA = numA.replaceFirst(RegExp(r'^0+(?=.)'), '');
      final trimmedB = numB.replaceFirst(RegExp(r'^0+(?=.)'), '');
      if (trimmedA.length != trimmedB.length) {
        return trimmedA.length - trimmedB.length;
      }
      final cmp = trimmedA.compareTo(trimmedB);
      if (cmp != 0) return cmp;
      continue;
    }

    final la = _lower(ca);
    final lb = _lower(cb);
    if (la != lb) return la - lb;
    i++;
    j++;
  }
  return (a.length - i) - (b.length - j);
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// ASCII lowercase. Enough for the comparison: anything outside it falls
/// through to its own code unit, which still gives a stable total order.
int _lower(int c) => (c >= 0x41 && c <= 0x5A) ? c + 0x20 : c;
