import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend.dart';
import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';
import '../../../shared/sondr_action.dart';
import '../../../shared/sondr_error.dart';
import '../../../shared/sondr_field.dart';
import '../../../shared/sondr_loading.dart';
import '../../../shared/sondr_notice.dart';
import '../../../shared/sondr_swipe_row.dart';
import '../../../core/utils/relative_time.dart';
import '../../profile/other_profile_screen.dart';
import '../../reports/report.dart';
import '../../reports/report_flow.dart';
import '../comment_threads.dart';
import '../models/comment.dart';
import '../posts_repository.dart';

/// Opens the comments for [postId] as a draggable bottom sheet.
Future<void> showCommentsSheet(BuildContext context, String postId) {
  final tokens = GreyscaleTokens.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    // Never under the status bar. Without this the sheet is free to reach the
    // very top of the screen, which is how its grab handle ended up at y=14
    // — unreachable, on a sheet with no other way out.
    useSafeArea: true,
    // A CONSTRAINT, not a fixed height (the pattern day_detail_sheet uses).
    // The sheet was a SizedBox of 0.7 screen inside a Padding carrying the
    // keyboard inset: 0.7 + the keyboard came to more than the screen, so the
    // box was clamped, the sheet filled the display and the whole column slid
    // up under the status bar. Capped instead, the keyboard inset is spent
    // INSIDE the 0.7 and the sheet's top never moves.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * _kSheetHeightFraction,
    ),
    // Background, not surface: the composer's field is a SURFACE capsule, and
    // on a surface-toned sheet it disappeared completely — leaving Post
    // floating beside nothing. The sheet is a page; the capsule sits on it.
    backgroundColor: tokens.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => CommentsSheet(postId: postId),
  );
}

/// How much of the screen the sheet takes — in BOTH keyboard states, so its
/// top edge never moves and the feed stays visible above it.
const double _kSheetHeightFraction = 0.7;

/// The comment body's size, shared with the composer so what you type and
/// what you read are the same text.
const double _kCommentBody = 13;

/// Structural air above and below the composer row.
///
/// Small, because the row is NOT just its text: Post carries 12 of tap
/// padding inside it, so the gap you SEE is this plus that — 18, one step up
/// from the 12 between comments. Setting this to 16 measured correctly and
/// looked like a section break.
const double _kComposerGap = kSpacingPair;

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  final _replyKey = GlobalKey();
  bool _busy = false;

  /// The comment being replied to, if any: its thread gets a composer of
  /// its own, directly beneath its last reply. One at a time — another
  /// Reply moves it. A reply to a reply attaches to the same parent; see
  /// [replyParentOf].
  Comment? _replyTo;

  void _startReply(Comment c) {
    // The top composer gives way: emptied, and the cursor leaves it.
    _input.clear();
    _inputFocus.unfocus();
    setState(() => _replyTo = c);
    // After the frame that builds it: focus, and bring the parent and the
    // composer into view above the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _replyTo != c) return;
      // Focus is applied here and now, so the field's own "show my caret"
      // scroll is scheduled BEFORE ours for the next frame — and ours, the
      // one that knows about the clearance, is the one that lands.
      _replyFocus.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _replyTo != c) return;
        _revealReply(
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: const Duration(milliseconds: 180),
        );
      });
    });
  }

  /// Scrolls the reply composer's box — field, word, and the clearance
  /// beneath — to the bottom of the list, which is the keyboard's top edge.
  /// With [ScrollPositionAlignmentPolicy.keepVisibleAtEnd] it only scrolls
  /// when the box has slipped below, which is what typing wants: the field
  /// grows down into the keyboard and is brought back, nothing else moves.
  void _revealReply({
    required ScrollPositionAlignmentPolicy alignmentPolicy,
    Duration duration = Duration.zero,
  }) {
    final ctx = _replyKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 1,
      alignmentPolicy: alignmentPolicy,
      duration: duration,
    );
  }

  /// Close on the reply composer: it goes, and the keyboard with it.
  void _closeReply() {
    _reply.clear();
    _replyFocus.unfocus();
    setState(() => _replyTo = null);
  }

  /// Close on the top composer: emptied, and the keyboard goes.
  void _closeInput() {
    _input.clear();
    _inputFocus.unfocus();
  }
  bool _hasText = false;
  String? _error;

  /// Whether the line under the composer is a thank-you rather than a
  /// failure. One tone each: see [SondrNotice].
  bool _noticeIsQuiet = false;

  /// Guards the FIRST emission only.
  ///
  /// `snapshots()` promises no event within any time bound: offline with
  /// nothing cached for this subcollection, or against an unreachable
  /// network, it yields no data AND no error, and the sheet sat on
  /// "Loading…" forever. A `Stream.timeout` is the wrong tool — it restarts
  /// on every event, so a healthy stream that has delivered its comments and
  /// gone quiet would be killed mid-life. This times out the WAIT, not the
  /// stream, and a late first event still wins (data takes the branch).
  static const _loadWindow = Duration(seconds: 10);
  Timer? _loadTimer;
  bool _loadTimedOut = false;

  @override
  void initState() {
    super.initState();
    // Post is grey until there is something to post, so the field's emptiness
    // has to be state the sheet rebuilds on.
    _loadTimer = Timer(_loadWindow, () {
      if (!mounted) return;
      if (ref.read(postCommentsProvider(widget.postId)).isLoading) {
        setState(() => _loadTimedOut = true);
      }
    });
    _reply.addListener(() {
      if (!mounted) return;
      setState(() {});
      // A second or third line grows the field downwards; after the frame
      // that lays it out, keep the same clearance above the keyboard.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _replyTo == null) return;
        _revealReply(
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      });
    });
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      // Editing is the retry, so it clears the last failure.
      if (has != _hasText || _error != null) {
        setState(() {
          _hasText = has;
          _error = null;
          _noticeIsQuiet = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _send() => _post(_input, parent: null);

  Future<void> _sendReply() async {
    final target = _replyTo;
    if (target == null) return;
    await _post(_reply, parent: replyParentOf(target));
  }

  Future<void> _post(TextEditingController from, {required String? parent}) async {
    final text = from.text.trim();
    final repo = ref.read(postsRepositoryProvider);
    if (text.isEmpty || repo == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _noticeIsQuiet = false;
    });
    try {
      await repo.addComment(widget.postId, text, parentId: parent);
      from.clear();
      if (mounted && parent != null) setState(() => _replyTo = null);
    } on FirebaseException catch (e) {
      debugPrint('SONDR comment error: ${e.code} :: ${e.message}');
      if (mounted) setState(() => _error = 'Couldn’t post comment.');
    } catch (e) {
      debugPrint('SONDR comment error: $e');
      if (mounted) setState(() => _error = 'Couldn’t post comment.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Report somebody else's comment: ask why, send, and let the thread
  /// drop it. The sheet's own error line carries the answer either way —
  /// a failure hides nothing.
  Future<void> _report(Comment c) async {
    SondrSwipeRow.close(context);
    final outcome = await reportThing(
      context,
      ref,
      type: ReportTarget.comment,
      targetKey: reportTargetKey(
        type: ReportTarget.comment,
        id: c.id,
        postId: widget.postId,
      ),
      targetOwnerUid: c.authorUid,
      title: reportTitle(ReportTarget.comment),
    );
    if (!mounted) return;
    switch (outcome) {
      case ReportOutcome.cancelled:
        break;
      case ReportOutcome.sent:
        setState(() {
          _error = kReportThanks;
          _noticeIsQuiet = true;
        });
      case ReportOutcome.failed:
        setState(() {
          _error = kReportFailed;
          _noticeIsQuiet = false;
        });
    }
  }

  Future<void> _delete(String commentId) async {
    final repo = ref.read(postsRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.deleteComment(widget.postId, commentId);
    } catch (_) {/* ignore — the stream stays as-is on failure */}
  }

  /// A read that failed or never arrived — the same wording either way,
  /// because to the reader they are the same thing.
  Widget _loadFailed() => const Center(
        child: SondrError('Couldn’t load comments.', textAlign: TextAlign.center),
      );

  /// The top composer: a bare field, and one word at its right — Close
  /// while it is empty, Post once there is something to post.
  Widget _composer(double scale) => _Composer(
    controller: _input,
    focusNode: _inputFocus,
    busy: _busy,
    autofocus: true,
    onPost: _send,
    onClose: _closeInput,
    scale: scale,
  );

  /// The reply composer, beneath the thread it answers. It is laid out
  /// exactly as the top composer is — full width, the field centred, the
  /// word at the same right edge — so the cursor sits on the same line
  /// down the sheet. Only the replies themselves are indented.
  ///
  /// Beneath it, the same air a comment row leaves under its text. The
  /// composer's inside is symmetric, so with this the clearance between the
  /// cursor and the keyboard equals the gap between the text above and the
  /// cursor: one rhythm, whichever side of the field you read.
  Widget _replyComposer(double scale) => Padding(
    key: _replyKey,
    padding: EdgeInsets.only(bottom: kSpacingPair * scale),
    child: _Composer(
      controller: _reply,
      focusNode: _replyFocus,
      busy: _busy,
      autofocus: false,
      onPost: _sendReply,
      onClose: _closeReply,
      // The sheet scrolls the composer into view itself; the field must not
      // add the platform's 20 on top and overshoot the clearance.
      scrollPadding: EdgeInsets.zero,
      scale: scale,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    final theme = Theme.of(context);
    final uid = ref.watch(currentUidProvider);
    final comments = ref.watch(postCommentsProvider(widget.postId));

    // Fill the capped height, so the sheet's top edge is the same with the
    // keyboard up and down. The keyboard inset is taken from INSIDE that
    // height — the content area shrinks rather than the sheet growing — which
    // is the whole difference between this and the version that slid up under
    // the status bar.
    return SizedBox.expand(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              // One rhythm down the head of the sheet: grabber, title, list
              // are all a base unit apart. The three hand-picked gaps that
              // were here (10 / 12 / 8) were what made it read unsettled.
              SizedBox(height: kSpacingBase * scale),
              Container(
                width: 36 * scale,
                height: 4 * scale,
                decoration: BoxDecoration(
                  color: tokens.ringTrack,
                  borderRadius: BorderRadius.circular(2 * scale),
                ),
              ),
              SizedBox(height: kSpacingBase * scale),
              Text(
                'Comments',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              SizedBox(height: _kComposerGap * scale),
              _composer(scale),
              // The failure sits under the composer that caused it, and stays
              // until the next keystroke — no floating surface, no timeout.
              if (_error != null) ...[
                SizedBox(height: kSpacingPair * scale),
                if (_noticeIsQuiet)
                  SondrNotice(_error!, textAlign: TextAlign.center)
                else
                  SondrError(_error!, textAlign: TextAlign.center),
              ],
              SizedBox(height: _kComposerGap * scale),
              Expanded(
                child: comments.when(
                  // Three terminal states and no fourth: a list, an empty
                  // list, or a failure. Waiting is not one of them past
                  // [_loadWindow].
                  loading: () =>
                      _loadTimedOut ? _loadFailed() : const SondrLoading(),
                  error: (_, _) => _loadFailed(),
                  data: (list) {
                    // Nothing to say about nothing. An empty list is just
                    // empty space under the composer, which is already an
                    // invitation to type.
                    if (list.isEmpty) return const SizedBox.shrink();
                    return ListView.builder(
                      padding: EdgeInsets.zero,
                      // Pulling the list puts the keyboard away.
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: threadOf(list).length,
                      itemBuilder: (_, i) {
                        final thread = threadOf(list);
                        final entry = thread[i];
                        final c = entry.comment;
                        final tile = _CommentTile(
                          comment: c,
                          depth: entry.depth,
                          onReply: () => _startReply(c),
                        );
                        // The reply composer sits after the LAST entry of
                        // the thread being answered.
                        final target = _replyTo;
                        final parentId = target == null ? null : replyParentOf(target);
                        final lastOfThread = parentId != null &&
                            (c.id == parentId || c.parentId == parentId) &&
                            (i + 1 == thread.length ||
                                thread[i + 1].comment.parentId != parentId &&
                                    thread[i + 1].comment.id != parentId);
                        if (lastOfThread) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _row(c, tile, uid),
                              _replyComposer(scale),
                            ],
                          );
                        }
                        return _row(c, tile, uid);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A comment's row: the tile, with Delete or Report under the swipe.
  Widget _row(Comment c, Widget tile, String? uid) {
    final own = c.authorUid == uid;
    return SondrSwipeRow(
      trayInset: kSpacingPair,
      haptic: true,
      actions: [
        SondrAction(
          label: own ? 'Delete' : 'Report',
          fontSize: kRowActionSize,
          onPressed: own ? () => _delete(c.id) : () => _report(c),
        ),
      ],
      child: tile,
    );
  }

}

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.comment,
    this.depth = 0,
    this.onReply,
  });

  final Comment comment;

  /// 1 for a reply: the row starts 24 beyond its parent's text, which
  /// begins after the gutter, the avatar and the gap.
  final int depth;
  final VoidCallback? onReply;

  static const double _replyInset = 24 + kAvatarComment + kSpacingBase + 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    final theme = Theme.of(context);
    final initial = comment.author.label.isNotEmpty
        ? comment.author.label[0].toUpperCase()
        : '?';

    return Padding(
      // The row carries the app's 24 gutter itself so the swipe tray can open
      // into it; a reply starts 24 beyond its parent's text.
      padding: EdgeInsets.fromLTRB(
        (depth > 0 ? _replyInset : 24) * scale,
        kSpacingPair * scale,
        24 * scale,
        kSpacingPair * scale,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The avatar and the name are the way to whoever wrote this.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openProfile(
              context,
              ref,
              comment.authorUid,
              handle: comment.author.username,
              displayName: comment.author.displayName,
            ),
            child: CircleAvatar(
            radius: kAvatarComment / 2 * scale,
            // Surface on a background-toned sheet, the same way a friend row
            // draws its placeholder — background-on-background left the
            // initial floating with no disc behind it.
            backgroundColor: tokens.surface,
            child: Text(
              initial,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                color: tokens.textSecondary,
              ),
            ),
            ),
          ),
          SizedBox(width: kSpacingBase * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => openProfile(
                        context,
                        ref,
                        comment.authorUid,
                        handle: comment.author.username,
                        displayName: comment.author.displayName,
                      ),
                      child: Text(
                        comment.author.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15 * scale,
                          fontWeight: FontWeight.w700,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(width: kSpacingPair * scale),
                    if (comment.createdAt != null)
                      Text(
                        RelativeTime.of(comment.createdAt!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.w700,
                          color: tokens.textTertiary,
                        ),
                      ),
                    // The way to answer, as quiet as the time beside it.
                    if (onReply != null) ...[
                      SizedBox(width: kSpacingPair * scale),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onReply,
                        child: Text(
                          'Reply',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12 * scale,
                            fontWeight: FontWeight.w700,
                            color: tokens.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: kSpacingPair * scale),
                Text(
                  comment.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: _kCommentBody * scale,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How far above the keyboard the reply composer's cursor line sits — a
/// row's air beneath the text plus the composer's own padding over the
/// field — in [context]. The one clearance a field typed above the
/// keyboard keeps, here and on the milestone's final look.
double replyComposerClearance(BuildContext context) {
  final scale = figmaScale(context);
  final lineHeight = SondrField.lineHeightOf(context, fontSize: _kCommentBody);
  return kSpacingPair * scale + _Composer._pad(context, scale, lineHeight);
}

/// A bare field with one word at its right: Close while empty, Post once
/// there is something to post. The word is mirrored by an invisible twin
/// on the left, so the field is centred by construction.
///
/// The field's air above and below is one figure, [_pad], settled before
/// layout from the word's height and the line's: the word is centred on the
/// FIRST line, and a second or third line grows the field downwards with
/// the first line, the word and the air above all standing still. The air
/// below the last line is that same figure, whatever the count.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.autofocus,
    required this.onPost,
    required this.onClose,
    required this.scale,
    this.scrollPadding,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool autofocus;
  final VoidCallback onPost;
  final VoidCallback onClose;
  final double scale;
  final EdgeInsets? scrollPadding;

  /// The field's padding above and below: enough that the word's tap target
  /// fits beside one line, and never less than a row's own.
  static double _pad(BuildContext context, double scale, double lineHeight) =>
      math.max(
        kSpacingPair * scale,
        (SondrAction.heightOf(context) - lineHeight) / 2,
      );

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;
    final lineHeight = SondrField.lineHeightOf(context, fontSize: _kCommentBody);
    final pad = _pad(context, scale, lineHeight);
    // The word, centred on the first line's box.
    Widget onFirstLine(Widget word) => SizedBox(
      height: lineHeight + 2 * pad,
      child: Center(child: word),
    );
    final word = hasText
        ? SondrAction(
            label: 'Post',
            weight: FontWeight.w700,
            onPressed: busy ? null : onPost,
          )
        : SondrAction(
            label: 'Close',
            supporting: true,
            weight: FontWeight.w700,
            onPressed: busy ? null : onClose,
          );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: kSpacingPair * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          onFirstLine(
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: word,
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: pad),
              child: SondrField(
                controller: controller,
                focusNode: focusNode,
                enabled: !busy,
                filled: false,
                centered: true,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                autofocus: autofocus,
                fontSize: _kCommentBody,
                scrollPadding: scrollPadding,
              ),
            ),
          ),
          onFirstLine(word),
        ],
      ),
    );
  }
}
