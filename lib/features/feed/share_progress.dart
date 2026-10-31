import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_prompt.dart';
import 'firebase_share_backend.dart';
import 'share_job.dart';

/// The one line the feed gives a share, top left, where "Notifications"
/// stands at the right and in its style: how far the upload has got, then
/// "Posted" for a moment, or — when the job has given up — that it could
/// not, with a word to try again and a word to discard it; or, once, that
/// a job left from before could not be finished and has been thrown
/// away. Nothing else of a share shows in the feed until the post itself
/// does, complete.

enum ShareLineKind { uploading, posted, failed, discarded }

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
/// then a job thrown away, then a post just written. Null when there is
/// nothing.
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
  if (states.values.any((s) => s.status == ShareJobStatus.discarded)) {
    return const ShareLine(ShareLineKind.discarded);
  }
  return const ShareLine(ShareLineKind.posted);
}

/// What the line prints.
String uploadingText(int percent) => 'Uploading your post $percent%';
const String kPostedText = 'Posted';
const String kCouldNotPostText = 'Couldn’t post · ';
const String kTryAgainText = 'Try again';
const String kDiscardText = 'Discard';
const String kDiscardedText = 'A post couldn’t be finished';

/// What the line says when a post has been deleted — wherever the delete
/// was done from, read on the Feed when the person next looks at it.
const String kPostDeletedText = 'Post deleted';

/// What Discard asks before it does anything.
const String kDiscardTitle = 'Discard this post?';
const String kDiscardBody = 'Its photos stay in your milestones.';

/// How long "Posted" stands, and how long it takes to go; how long the
/// word about a discarded job stands.
const Duration kPostedHold = Duration(seconds: 2);
const Duration kPostedFade = Duration(milliseconds: 300);
const Duration kDiscardedHold = Duration(seconds: 3);

/// A post was deleted. The Feed's line says so once, in the same place
/// and for the same two seconds as "Posted", whichever screen the delete
/// was done from: the count moves, the line reads it, and the line is
/// the only thing that holds how long it shows.
class PostDeleted extends Notifier<int> {
  @override
  int build() => 0;

  void say() => state = state + 1;
}

final postDeletedProvider = NotifierProvider<PostDeleted, int>(PostDeleted.new);

class ShareProgressLine extends ConsumerStatefulWidget {
  const ShareProgressLine({super.key});

  @override
  ConsumerState<ShareProgressLine> createState() => _ShareProgressLineState();
}

class _ShareProgressLineState extends ConsumerState<ShareProgressLine> {
  /// The jobs seen uploading, so a post that lands and is gone between
  /// two frames still gets its "Posted".
  final Set<String> _uploading = {};

  /// The word being held — "Posted", or "Post deleted" — until it fades.
  /// Null when there is none.
  String? _flashText;
  bool _fading = false;
  Timer? _timer;

  /// The last delete the line has already spoken for, so a rebuild for
  /// any other reason does not say it again.
  int _deletesSaid = 0;

  /// The jobs thrown away that the line is telling of, held and then
  /// faded once, and dismissed with the runner so they are never told
  /// of again.
  final Set<String> _discarded = {};
  bool _discardedShowing = false;
  bool _discardedFading = false;
  Timer? _discardedTimer;

  @override
  void dispose() {
    _timer?.cancel();
    _discardedTimer?.cancel();
    super.dispose();
  }

  void _tellDiscarded() {
    _discardedShowing = true;
    _discardedFading = false;
    _discardedTimer?.cancel();
    _discardedTimer = Timer(kDiscardedHold, () {
      if (!mounted) return;
      setState(() => _discardedFading = true);
      _discardedTimer = Timer(kPostedFade, () {
        if (!mounted) return;
        final runner = ref.read(shareJobRunnerProvider);
        for (final id in _discarded) {
          runner?.dismiss(id);
        }
        setState(() {
          _discarded.clear();
          _discardedShowing = false;
          _discardedFading = false;
        });
      });
    });
  }

  Future<void> _discard() async {
    final yes = await showSondrConfirm(
      context,
      title: kDiscardTitle,
      body: kDiscardBody,
      confirmLabel: kDiscardText,
    );
    if (!yes || !mounted) return;
    await ref.read(shareJobRunnerProvider)?.discardFailed();
  }

  /// Two seconds of [text], then three hundred milliseconds of going.
  void _flash(String text) {
    _flashText = text;
    _fading = false;
    _timer?.cancel();
    _timer = Timer(kPostedHold, () {
      if (!mounted) return;
      setState(() => _fading = true);
      _timer = Timer(kPostedFade, () {
        if (!mounted) return;
        setState(() {
          _flashText = null;
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
    // A delete, from wherever it was done. Counted rather than flagged,
    // so one that happens while the Feed is off screen is still said the
    // moment it comes back.
    final deletes = ref.watch(postDeletedProvider);
    if (deletes != _deletesSaid) {
      _deletesSaid = deletes;
      _flash(kPostDeletedText);
    }

    final line = shareLineOf(states);
    if (landed || (line?.kind == ShareLineKind.posted && _flashText == null)) {
      _flash(kPostedText);
    }
    var newlyDiscarded = false;
    for (final e in states.entries) {
      if (e.value.status == ShareJobStatus.discarded && _discarded.add(e.key)) newlyDiscarded = true;
    }
    if (newlyDiscarded && !_discardedShowing) _tellDiscarded();

    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13 * scale,
      fontWeight: FontWeight.w600,
      color: tokens.textSecondary,
    );

    Widget? text;
    final word = style?.copyWith(color: tokens.textPrimary, fontWeight: FontWeight.w700);
    if (line?.kind == ShareLineKind.failed) {
      text = Text.rich(
        TextSpan(
          text: kCouldNotPostText,
          style: style,
          children: [
            TextSpan(
              text: kTryAgainText,
              style: word,
              recognizer: TapGestureRecognizer()
                ..onTap = () => ref.read(shareJobRunnerProvider)?.retryFailed(),
            ),
            TextSpan(text: ' · ', style: style),
            TextSpan(
              text: kDiscardText,
              style: word,
              recognizer: TapGestureRecognizer()..onTap = _discard,
            ),
          ],
        ),
      );
    } else if (line?.kind == ShareLineKind.uploading) {
      text = Text(uploadingText(line!.percent), style: style);
    } else if (_discardedShowing) {
      text = AnimatedOpacity(
        opacity: _discardedFading ? 0 : 1,
        duration: kPostedFade,
        child: Text(kDiscardedText, style: style?.copyWith(color: tokens.textTertiary)),
      );
    } else if (_flashText != null) {
      text = AnimatedOpacity(
        opacity: _fading ? 0 : 1,
        duration: kPostedFade,
        child: Text(_flashText!, style: style?.copyWith(color: tokens.textPrimary)),
      );
    }
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.fromLTRB(16 * scale, 0, 0, 8 * scale),
      child: Align(alignment: Alignment.centerLeft, child: text),
    );
  }
}
