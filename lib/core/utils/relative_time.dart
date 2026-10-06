/// Compact "time ago" for feed timestamps — "now", "5m", "2h", "3d", "2w",
/// then an absolute-ish month count. Kept short so it sits quietly beside the
/// author name; effort is the content, not the clock.
abstract final class RelativeTime {
  static String of(DateTime when, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final d = ref.difference(when);
    if (d.inSeconds < 45) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    if (d.inDays < 30) return '${d.inDays ~/ 7}w';
    if (d.inDays < 365) return '${d.inDays ~/ 30}mo';
    return '${d.inDays ~/ 365}y';
  }
}
