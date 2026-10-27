import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import '../feed/band_story.dart' show SegmentUnit;
import '../feed/models/post.dart';
import '../feed/widgets/milestone_card.dart';
import 'capture_review_screen.dart' show kCaptionMaxLength;
import 'milestone_arrange_screen.dart' show kArrangeGutter, kArrangeTop;

/// The final look: the card exactly as friends will see it — the handle,
/// "now", the pages a tap steps through, the dots, Like and Comments —
/// with the caption typed beneath it and appearing on the card as it is
/// typed. Share posts it; Keep saves the shot privately instead; Back
/// returns to Arrange with everything kept.

enum FinalLookOutcomeKind { back, kept, shared }

@immutable
class FinalLookOutcome {
  const FinalLookOutcome(this.kind);
  final FinalLookOutcomeKind kind;
}

const String kCaptionHint = 'Add a caption';
const Key kFinalLookCaptionKey = Key('sondr-final-look-caption');

class MilestoneFinalLookScreen extends ConsumerStatefulWidget {
  const MilestoneFinalLookScreen({
    super.key,
    required this.photos,
    required this.milestoneHours,
    required this.taskName,
    required this.handle,
    this.segments = const [],
    this.unit,
    this.onKeep,
    this.onShare,
  });

  /// The post's photos in the arranged order, each with its framing and
  /// its session; the new shot as a file:// URL until it is uploaded.
  final List<PostPhoto> photos;
  final int milestoneHours;
  final String taskName;

  /// Whose card it is: the handle the top row prints.
  final String handle;

  /// The band's story, so the photo pages say their sessions as the
  /// posted card will.
  final List<PostSegment> segments;
  final SegmentUnit? unit;

  /// Saves the shot privately. Returns false to keep the screen up.
  final Future<bool> Function(WidgetRef ref)? onKeep;

  /// Posts with [caption]. Returns false to keep the screen up.
  final Future<bool> Function(WidgetRef ref, String? caption)? onShare;

  @override
  ConsumerState<MilestoneFinalLookScreen> createState() => _MilestoneFinalLookScreenState();
}

class _MilestoneFinalLookScreenState extends ConsumerState<MilestoneFinalLookScreen> {
  final TextEditingController _caption = TextEditingController();
  final FocusNode _captionFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  _Working? _working;
  String? _error;

  bool get _busy => _working != null;

  @override
  void initState() {
    super.initState();
    // The card shows the caption as it is typed.
    _caption.addListener(() => setState(() {}));
    // Typing must not put the field behind the keyboard: the card scrolls
    // up to make room.
    _captionFocus.addListener(() {
      if (!_captionFocus.hasFocus || !_scroll.hasClients) return;
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
    _caption.dispose();
    _captionFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The post as it will be, for the card to draw.
  MilestonePost get _preview {
    final text = _caption.text.trim();
    return MilestonePost(
      id: 'preview',
      // Not the viewer's own: friends see Like, not Likes.
      authorUid: 'preview',
      author: PostAuthor(username: widget.handle, displayName: ''),
      createdAt: DateTime.now(),
      caption: text.isEmpty ? null : text,
      photos: widget.photos,
      taskName: widget.taskName,
      milestoneHours: widget.milestoneHours,
      totalHours: widget.milestoneHours,
      segments: widget.segments,
      unit: widget.unit,
    );
  }

  Future<void> _keep() async {
    if (_busy) return;
    setState(() => _working = _Working.keeping);
    final ok = await widget.onKeep?.call(ref) ?? true;
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _working = null;
        _error = 'Couldn’t save the photo. Please try again.';
      });
      return;
    }
    Navigator.of(context).pop(const FinalLookOutcome(FinalLookOutcomeKind.kept));
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _working = _Working.sharing);
    final text = _caption.text.trim();
    final ok = await widget.onShare?.call(ref, text.isEmpty ? null : text) ?? true;
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _working = null;
        _error = 'Couldn’t create the post. Please try again.';
      });
      return;
    }
    Navigator.of(context).pop(const FinalLookOutcome(FinalLookOutcomeKind.shared));
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
            SizedBox(height: kArrangeTop * scale),
            Row(
              children: [
                SondrAction(
                  label: 'Back',
                  supporting: true,
                  fontSize: 14,
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(
                            const FinalLookOutcome(FinalLookOutcomeKind.back),
                          ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: kArrangeGutter),
                      child: MilestoneCard(post: _preview, opensPost: false, preview: true),
                    ),
                    SizedBox(height: 12 * scale),
                    _captionField(tokens, theme, scale),
                    SizedBox(height: 12 * scale),
                  ],
                ),
              ),
            ),
            if (_error != null) ...[
              SondrError(_error!, textAlign: TextAlign.center),
              SizedBox(height: 6 * scale),
            ],
            // Share above Keep, where the review puts them.
            Center(
              child: SondrAction(
                label: _working == _Working.sharing ? 'Sharing…' : 'Share',
                onPressed: _busy ? null : _share,
              ),
            ),
            Center(
              child: SondrAction(
                label: _working == _Working.keeping ? 'Keeping…' : 'Keep',
                supporting: true,
                onPressed: _busy ? null : _keep,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A bare field: no box, no line, the words centred.
  Widget _captionField(GreyscaleTokens tokens, ThemeData theme, double scale) {
    // 14, unscaled, as the card's own numbers are.
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      color: tokens.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kArrangeGutter),
      child: TextField(
        key: kFinalLookCaptionKey,
        controller: _caption,
        focusNode: _captionFocus,
        maxLines: 3,
        minLines: 1,
        textAlign: TextAlign.center,
        inputFormatters: [LengthLimitingTextInputFormatter(kCaptionMaxLength)],
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        style: style,
        cursorColor: tokens.textPrimary,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8 * scale),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: kCaptionHint,
          hintStyle: style?.copyWith(color: tokens.textTertiary),
        ),
      ),
    );
  }
}

enum _Working { keeping, sharing }
