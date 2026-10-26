import 'dart:async';

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
  bool _busy = false;

  /// The comment being replied to, if any. A reply to a reply attaches to
  /// the same parent; see [replyParentOf].
  Comment? _replyTo;

  void _startReply(Comment c) {
    setState(() => _replyTo = c);
    _inputFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyTo = null);
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
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final repo = ref.read(postsRepositoryProvider);
    if (text.isEmpty || repo == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _noticeIsQuiet = false;
    });
    try {
      final target = _replyTo;
      await repo.addComment(
        widget.postId,
        text,
        parentId: target == null ? null : replyParentOf(target),
      );
      _input.clear();
      if (mounted) setState(() => _replyTo = null);
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

  /// The composer: a borderless centred field with Post to its right.
  ///
  /// Post is MIRRORED by an invisible copy on the left. Without it the field
  /// would be centred in what Post leaves over, pushing the cursor left of
  /// the screen's true centre; an invisible twin is exact by construction,
  /// where a hand-set width would drift with the font and the scale factor.
  Widget _composer(double scale) {
    final post = SondrAction(
      label: 'Post',
      // Tone alone says whether there is anything to post — the weight stays
      // bold either way, like Like/Liked on a feed card.
      supporting: !_hasText,
      weight: FontWeight.w700,
      onPressed: _hasText && !_busy ? _send : null,
    );

    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final replyTo = _replyTo;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: kSpacingPair * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Who the reply is to, with the way out of it. Quiet, above the
          // field; the field itself does not move.
          if (replyTo != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                kSpacingPair * scale, 0, kSpacingPair * scale, kSpacingPair * scale,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying to ${replyTo.author.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12 * scale,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _cancelReply,
                    child: Text(
                      'Cancel',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w700,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: post,
          ),
          Expanded(
            // The field's own air. On one line Post's taller tap target sets
            // the row height and this does nothing; once the text wraps past
            // that height the field drives the row, and without this the
            // first line climbs up against the title.
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: kSpacingPair * scale),
                child: SondrField(
                controller: _input,
                focusNode: _inputFocus,
                enabled: !_busy,
                // No capsule: the sheet's own heading says what this takes, so
                // a container would only add furniture (as on Add Friends).
                filled: false,
                centered: true,
                // Grows a line at a time to a ceiling of three, then holds
                // its height and scrolls inside itself. EditableText keeps
                // the cursor in view on its own, so the newest line stays
                // visible without a ScrollController of ours.
                minLines: 1,
                maxLines: 3,
                // Return closes the keyboard, exactly as the caption screen's
                // field does — it does NOT send, and it does not insert a
                // line either. Post is the only way to send, and with the
                // keyboard gone the comments you were joining are visible
                // again. Long text still wraps to the three-line ceiling as
                // you type.
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                // Open ready to type: the sheet was asked for, so the
                // cursor is already in it. Nothing else moves.
                autofocus: true,
                hint: 'Add a comment',
                // What you type is the size of what you are joining.
                fontSize: _kCommentBody,
              ),
            ),
          ),
          post,
        ],
          ),
        ],
      ),
    );
  }

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
                        final entry = threadOf(list)[i];
                        final c = entry.comment;
                        final tile = _CommentTile(
                          comment: c,
                          depth: entry.depth,
                          onReply: () => _startReply(c),
                        );
                        // The swipe hides the action, exactly as a friend
                        // row hides Remove and Block: Delete on your own
                        // comment, Report on somebody else's. An
                        // affordance on every comment would be clutter on
                        // the common case.
                        final own = c.authorUid == uid;
                        return SondrSwipeRow(
                          // The composer's own horizontal inset, so the
                          // action a swipe reveals has its right edge
                          // exactly where Post's is — the two are the only
                          // controls on this sheet, one above the other.
                          trayInset: kSpacingPair,
                          actions: [
                            SondrAction(
                              label: own ? 'Delete' : 'Report',
                              fontSize: kRowActionSize,
                              onPressed: own
                                  ? () => _delete(c.id)
                                  : () => _report(c),
                            ),
                          ],
                          child: tile,
                        );
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
