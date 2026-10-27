import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a share cost, step by step — debug tools only. Each mark is the
/// milliseconds since the one before, with the bytes moved where there
/// were any; two totals say how long until the post was on the author's
/// feed and how long until friends could see it.
class ShareTrace {
  ShareTrace(this.postId) : _started = DateTime.now();

  final String postId;
  final DateTime _started;
  DateTime _last = DateTime.now();
  final List<ShareMark> marks = [];
  int? timeToFeedMs;
  int? timeToFriendsMs;

  void mark(String label, {int? bytes}) {
    final now = DateTime.now();
    marks.add(ShareMark(label, now.difference(_last).inMilliseconds, bytes: bytes));
    _last = now;
  }

  void feedShown() => timeToFeedMs ??= DateTime.now().difference(_started).inMilliseconds;
  void friendsCanSee() => timeToFriendsMs ??= DateTime.now().difference(_started).inMilliseconds;

  int get totalMs => DateTime.now().difference(_started).inMilliseconds;

  /// One line per mark, monospaced-friendly.
  String report() {
    final b = StringBuffer();
    for (final m in marks) {
      b.writeln('${m.label.padRight(28)} ${m.ms.toString().padLeft(6)} ms'
          '${m.bytes == null ? '' : '  ${(m.bytes! / 1024).toStringAsFixed(0)} KB'}');
    }
    b.writeln('time to feed      ${timeToFeedMs ?? '-'} ms');
    b.writeln('time to friends   ${timeToFriendsMs ?? '-'} ms');
    return b.toString();
  }
}

@immutable
class ShareMark {
  const ShareMark(this.label, this.ms, {this.bytes});
  final String label;
  final int ms;
  final int? bytes;
}

/// The last share's trace, for the debug panel. Null until one has run.
class LastShareTrace extends Notifier<ShareTrace?> {
  @override
  ShareTrace? build() => null;

  void set(ShareTrace trace) => state = trace;
}

final lastShareTraceProvider = NotifierProvider<LastShareTrace, ShareTrace?>(LastShareTrace.new);
