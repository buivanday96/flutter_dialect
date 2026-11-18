/// Line-based unified diff (LCS), enough for previewing generated files.
library;

const _context = 3;

/// Unified diff from [before] to [after]. Empty when they are equal.
String unifiedDiff(
  String before,
  String after, {
  required String fromName,
  required String toName,
}) {
  if (before == after) return '';
  final a = _lines(before);
  final b = _lines(after);
  final ops = _ops(a, b);

  final out = StringBuffer()
    ..writeln('--- $fromName')
    ..writeln('+++ $toName');

  // Group changes into hunks with [_context] lines around them.
  var i = 0;
  while (i < ops.length) {
    if (ops[i].$1 == ' ') {
      i++;
      continue;
    }
    var start = i;
    var ctx = 0;
    while (start > 0 && ops[start - 1].$1 == ' ' && ctx < _context) {
      start--;
      ctx++;
    }
    // Extend while the next change is close enough to share context.
    var lastChange = i;
    for (var k = i + 1; k < ops.length; k++) {
      if (ops[k].$1 != ' ') {
        lastChange = k;
      } else if (k - lastChange > _context * 2) {
        break;
      }
    }
    final end = lastChange + 1 + _context < ops.length
        ? lastChange + 1 + _context
        : ops.length;
    final hunk = ops.sublist(start, end);
    final aStart = ops.sublist(0, start).where((o) => o.$1 != '+').length;
    final bStart = ops.sublist(0, start).where((o) => o.$1 != '-').length;
    final aLen = hunk.where((o) => o.$1 != '+').length;
    final bLen = hunk.where((o) => o.$1 != '-').length;
    out.writeln('@@ -${_range(aStart, aLen)} +${_range(bStart, bLen)} @@');
    for (final (kind, line) in hunk) {
      out.writeln('$kind$line');
    }
    i = end;
  }
  return out.toString();
}

String _range(int start, int len) =>
    len == 0 ? '$start,0' : (len == 1 ? '${start + 1}' : '${start + 1},$len');

List<String> _lines(String s) {
  if (s.isEmpty) return const [];
  final lines = s.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// Edit script as (' ' | '-' | '+', line).
List<(String, String)> _ops(List<String> a, List<String> b) {
  // Strip common prefix/suffix to keep the table small.
  var pre = 0;
  while (pre < a.length && pre < b.length && a[pre] == b[pre]) {
    pre++;
  }
  var suf = 0;
  while (suf < a.length - pre &&
      suf < b.length - pre &&
      a[a.length - 1 - suf] == b[b.length - 1 - suf]) {
    suf++;
  }
  final am = a.sublist(pre, a.length - suf);
  final bm = b.sublist(pre, b.length - suf);

  final middle = <(String, String)>[];
  if (am.length * bm.length > 4000000) {
    // Too big for a table: show as replace.
    middle
      ..addAll([for (final l in am) ('-', l)])
      ..addAll([for (final l in bm) ('+', l)]);
  } else {
    final n = am.length;
    final m = bm.length;
    final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        lcs[i][j] = am[i] == bm[j]
            ? lcs[i + 1][j + 1] + 1
            : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
      }
    }
    var i = 0;
    var j = 0;
    while (i < n && j < m) {
      if (am[i] == bm[j]) {
        middle.add((' ', am[i]));
        i++;
        j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        middle.add(('-', am[i++]));
      } else {
        middle.add(('+', bm[j++]));
      }
    }
    while (i < n) {
      middle.add(('-', am[i++]));
    }
    while (j < m) {
      middle.add(('+', bm[j++]));
    }
  }
  return [
    for (final l in a.sublist(0, pre)) (' ', l),
    ...middle,
    for (final l in a.sublist(a.length - suf)) (' ', l),
  ];
}
