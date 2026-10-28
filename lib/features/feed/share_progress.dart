import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import 'firebase_share_backend.dart';
import 'share_job.dart';

/// The one line the feed gives a share, top left, where "Notifications"
/// stands at the right and in its style: how far the upload has got, then
/// "Posted" for a moment, or — when the job has given up — that it could
/// not, and a word to try again. Nothing else of a share shows in the feed
/// until the post itself does, complete.

enum ShareLineKind { uploading, posted, failed }

@immutable
class ShareLine {
  const ShareLine(this.kind, {this.percent = 0});
  final ShareLineKind kind;

  /// Bytes up over bytes in all, as a whole percentage.
  final int percent;

  @override
  bool operator ==(Object other) =>
      other is ShareLine && other.kind == kind && other.percent == percent;

  @override
  int get hashCode => Object.hash(kind, percent);
}

/// What the line says for [states]: a failure outranks everything, an
/// upload in progress comes next (every running job's bytes together),
/// and a post just written is "posted". Null when there is nothing.
ShareLine? shareLineOf(Map<String, ShareJobState> states) {
  if (states.isEmpty) return null;
  if (states.values.any((s) => s.status == ShareJobStatus.failed)) {
    return const ShareLine(ShareLineKind.failed);
  }
  final active = [
    for (final s in states.values)
      if (s.status == ShareJobStatus.running || s.status == ShareJobStatus.waiting) s,
  ];
  if (active.isNotEmpty) {
    final total = active.fold<int>(0, (n, s) => n + s.totalBytes);
    final up = active.fold<int>(0, (n, s) => n + s.uploadedBytes);
    final percent = total == 0 ? 0 : (up * 100 ~/ total).clamp(0, 100);
    return ShareLine(ShareLineKind.uploading, percent: percent);
  }
  return const ShareLine(ShareLineKind.posted);
}

/// What the line prints.
String uploadingText(int percent) => 'Uploading your post $percent%';
const String kPostedText = 'Posted';
const String kCouldNotPostText = 'Couldn’t post · ';
const String kTryAgainText = 'Try again';

/// How long "Posted" stands, and how long it takes to go.
const Duration kPostedHold = Duration(seconds: 2);
const Duration kPostedFade = Duration(milliseconds: 300);

class ShareProgressLine extends ConsumerStatefulWidget {
  const ShareProgressLine({super.key});

  @override
  ConsumerState<ShareProgressLine> createState() => _ShareProgressLineState();
}

class _ShareProgressLineState extends ConsumerState<ShareProgressLine> {
  /// The jobs seen uploading, so a post that lands and is gone between
  /// two frames still gets its "Posted".
  final Set<String> _uploading = {};

  /// "Posted" is held until this, then fades.
  DateTime? _postedUntil;
  bool _fading = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _posted() {
    _postedUntil = DateTime.now().add(kPostedHold);
    _fading = false;
    _timer?.cancel();
    _timer = Timer(kPostedHold, () {
      if (!mounted) return;
      setState(() => _fading = true);
      _timer = Timer(kPostedFade, () {
        if (!mounted) return;
        setState(() {
          _postedUntil = null;
          _fading = false;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final states = ref.watch(shareStatesProvider);
    // A job that was uploading and is now posted or gone has landed.
    var landed = false;
    for (final id in _uploading.toList()) {
      final s = states[id];
      if (s == null || s.status == ShareJobStatus.posted) {
        _uploading.remove(id);
        landed = true;
      }
    }
    for (final e in states.entries) {
      if (e.value.status == ShareJobStatus.running || e.value.status == ShareJobStatus.waiting) {
        _uploading.add(e.key);
      }
    }
    final line = shareLineOf(states);
    if (landed || (line?.kind == ShareLineKind.posted && _postedUntil == null)) {
      _posted();
    }

    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13 * scale,
      fontWeight: FontWeight.w600,
      color: tokens.textSecondary,
    );

    Widget? text;
    if (line?.kind == ShareLineKind.failed) {
      text = Text.rich(
        TextSpan(
          text: kCouldNotPostText,
          style: style,
          children: [
            TextSpan(
              text: kTryAgainText,
              style: style?.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w700),
              recognizer: TapGestureRecognizer()
                ..onTap = () => ref.read(shareJobRunnerProvider)?.retryFailed(),
            ),
          ],
        ),
      );
    } else if (line?.kind == ShareLineKind.uploading) {
      text = Text(uploadingText(line!.percent), style: style);
    } else if (_postedUntil != null) {
      text = AnimatedOpacity(
        opacity: _fading ? 0 : 1,
        duration: kPostedFade,
        child: Text(kPostedText, style: style?.copyWith(color: tokens.textPrimary)),
      );
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(16 * scale, 0, 0, 8 * scale),
      child: Align(alignment: Alignment.centerLeft, child: text),
    );
  }
}
