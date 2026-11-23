import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import '../feed/widgets/comments_sheet.dart' show replyComposerClearance;

/// The shape of a final look, for a milestone and for a session alike: a
/// word or two at the top, the card as friends will see it, a bare caption
/// field beneath it with the words appearing on the card as typed, and
/// Share over Keep at the bottom — or, where sharing is locked, the reason
/// where Share would be and Keep alone. While the caption is typed, Share
/// and Keep leave the layout and the field keeps the reply composer's
/// clearance above the keyboard; when it closes, the layout is as it was.

/// The longest a caption may be. Enforced by a formatter rather than by
/// maxLength, which comes with a counter this app did not draw.
const int kCaptionMaxLength = 200;

const String kCaptionHint = 'Add a caption';
const Key kShareReviewCaptionKey = Key('sondr-share-review-caption');

/// The field's own air above and below its text.
const double kCaptionFieldPad = 8;

/// How long Share and Keep take to go, and to come back.
const Duration kShareReviewActionsFade = Duration(milliseconds: 150);

/// The feed's gutter: the card at the card's width.
const double kShareReviewGutter = 16;
const double kShareReviewTop = 12;

/// What was done.
enum ShareReviewResult { kept, shared }

class ShareReviewScaffold extends ConsumerStatefulWidget {
  const ShareReviewScaffold({
    super.key,
    required this.card,
    required this.onFinished,
    this.leading,
    this.trailing,
    this.lockedCopy,
    this.onShare,
    this.onKeep,
  });

  /// The card, drawn with the caption as it stands.
  final Widget Function(String? caption) card;

  /// Called once Keep or Share has succeeded; the screen pops.
  final void Function(ShareReviewResult result) onFinished;

  /// The words at the top: Back at the left, Retake at the right.
  final Widget? leading;
  final Widget? trailing;

  /// Why sharing is not offered, or null when it is. Locked, there is no
  /// caption to write either.
  final String? lockedCopy;

  /// Posts with the caption. Returns false to keep the screen up.
  final Future<bool> Function(WidgetRef ref, String? caption)? onShare;

  /// Saves privately. Returns false to keep the screen up.
  final Future<bool> Function(WidgetRef ref)? onKeep;

  bool get canShare => lockedCopy == null;

  @override
  ConsumerState<ShareReviewScaffold> createState() => ShareReviewScaffoldState();
}

/// Which action is in flight.
enum ShareReviewWorking { keeping, sharing }

class ShareReviewScaffoldState extends ConsumerState<ShareReviewScaffold> {
  final TextEditingController caption = TextEditingController();
  final FocusNode captionFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  ShareReviewWorking? working;
  String? _error;
  bool _typing = false;

  bool get busy => working != null;

  @override
  void initState() {
    super.initState();
    caption.addListener(() => setState(() {}));
    captionFocus.addListener(() {
      final typing = captionFocus.hasFocus;
      if (typing != _typing) setState(() => _typing = typing);
      if (!typing || !_scroll.hasClients) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    });
  }

  @override
  void dispose() {
    caption.dispose();
    captionFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? get _captionText {
    final t = caption.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _keep() async {
    if (busy) return;
    setState(() => working = ShareReviewWorking.keeping);
    final ok = await widget.onKeep?.call(ref) ?? true;
    if (!mounted) return;
    if (!ok) {
      setState(() {
        working = null;
        _error = 'Couldn’t save the photo. Please try again.';
      });
      return;
    }
    widget.onFinished(ShareReviewResult.kept);
  }

  Future<void> _share() async {
    if (busy) return;
    setState(() => working = ShareReviewWorking.sharing);
    final ok = await widget.onShare?.call(ref, _captionText) ?? true;
    if (!mounted) return;
    if (!ok) {
      setState(() {
        working = null;
        _error = 'Couldn’t create the post. Please try again.';
      });
      return;
    }
    widget.onFinished(ShareReviewResult.shared);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: kShareReviewTop * scale),
            Row(
              children: [
                ?widget.leading,
                const Spacer(),
                ?widget.trailing,
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: kShareReviewGutter),
                      child: AbsorbPointer(absorbing: busy, child: widget.card(_captionText)),
                    ),
                    SizedBox(height: 12 * scale),
                    if (widget.canShare) _captionField(tokens, theme, scale),
                    // Typing: the field's cursor line ends the reply
                    // composer's clearance above the keyboard, which is
                    // where this list now ends. Otherwise its own air.
                    SizedBox(
                      height: _typing
                          ? replyComposerClearance(context) - kCaptionFieldPad * scale
                          : 12 * scale,
                    ),
                  ],
                ),
              ),
            ),
            // Share and Keep go while the caption is typed — out of the
            // layout, not merely under the keyboard — and come back when it
            // closes, each way in a short fade.
            AnimatedSwitcher(
              duration: kShareReviewActionsFade,
              child: _typing
                  ? const SizedBox.shrink(key: ValueKey('typing'))
                  : Column(
                      key: const ValueKey('actions'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null) ...[
                          SondrError(_error!, textAlign: TextAlign.center),
                          SizedBox(height: 6 * scale),
                        ],
                        // Share above Keep; locked, the reason stands where
                        // Share would, and Keep is the one action.
                        if (widget.canShare)
                          Center(
                            child: SondrAction(
                              label: working == ShareReviewWorking.sharing ? 'Sharing…' : 'Share',
                              onPressed: busy ? null : _share,
                            ),
                          )
                        else
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 12 * scale),
                            child: Text(
                              widget.lockedCopy!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 12 * scale,
                                color: tokens.textTertiary,
                              ),
                            ),
                          ),
                        Center(
                          child: SondrAction(
                            label: working == ShareReviewWorking.keeping ? 'Keeping…' : 'Keep',
                            supporting: widget.canShare,
                            onPressed: busy ? null : _keep,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// A bare field: no box, no line, the words centred. 14, unscaled, as
  /// the card's own numbers are.
  Widget _captionField(GreyscaleTokens tokens, ThemeData theme, double scale) {
    final style = theme.textTheme.bodyMedium?.copyWith(fontSize: 14, color: tokens.textPrimary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kShareReviewGutter),
      child: TextField(
        key: kShareReviewCaptionKey,
        controller: caption,
        focusNode: captionFocus,
        maxLines: 3,
        minLines: 1,
        textAlign: TextAlign.center,
        inputFormatters: [LengthLimitingTextInputFormatter(kCaptionMaxLength)],
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        style: style,
        cursorColor: tokens.textPrimary,
        enabled: !busy,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: kCaptionFieldPad * scale),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          hintText: kCaptionHint,
          hintStyle: style?.copyWith(color: tokens.textTertiary),
        ),
      ),
    );
  }
}
