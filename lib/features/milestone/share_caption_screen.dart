import 'package:flutter/material.dart';

import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../shell/main_shell.dart';

/// Pop a share flow back to the shell and land on Home (tab 0) — the "Not now" /
/// decline-to-post exit, shared by the milestone and session flows.
void goHome(WidgetRef ref, BuildContext context) {
  ref.read(selectedTabProvider.notifier).set(0);
  Navigator.of(context).popUntil((r) => r.isFirst);
}

/// The final step of any share flow — an optional caption over a [preview] of
/// the post, then submit. Shared by the milestone and session flows: each passes
/// its own [preview] widget and an [onSubmit] that does the upload/copy + the
/// `create*Post` write. On success the whole flow pops back to the shell and
/// lands on Feed; the back arrow returns to wherever it was pushed from (the
/// milestone picker, or Home for a session). This screen owns the caption field,
/// the busy state, the error toast and the land-on-Feed — the callers just
/// describe *what* to preview and *how* to create.
class SharePostCaptionScreen extends ConsumerStatefulWidget {
  const SharePostCaptionScreen({
    super.key,
    required this.preview,
    required this.onSubmit,
    required this.hasPhoto,
    this.submitLabel = 'Create',
    this.submitBusyLabel = 'Creating…',
  });

  final Widget preview;
  final String submitLabel;
  final String submitBusyLabel;

  /// Whether a photo is actually in hand — captured and kept, or picked from
  /// the band. Decides what leaving without posting is CALLED: with a photo
  /// it is "Keep" (it is already yours), without one there is nothing to
  /// keep and it is merely "Not now".
  final bool hasPhoto;

  /// Does the actual post creation with the entered [caption] (null when blank).
  /// Given the screen's own [ref]. Throwing surfaces a generic error toast.
  final Future<void> Function(WidgetRef ref, String? caption) onSubmit;

  @override
  ConsumerState<SharePostCaptionScreen> createState() =>
      _SharePostCaptionScreenState();
}

class _SharePostCaptionScreenState
    extends ConsumerState<SharePostCaptionScreen> {
  final _caption = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// Leave without posting.
  ///
  /// Writes nothing, deliberately: a kept photo already saved to the task's
  /// private gallery inside showPhotoCapture, and the session was logged
  /// before this screen existed. Sharing to the feed is the only thing this
  /// screen adds, so declining it just closes the flow.
  void _exit() => Navigator.of(context).popUntil((r) => r.isFirst);

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final text = _caption.text.trim();
      await widget.onSubmit(ref, text.isEmpty ? null : text);
      if (!mounted) return;
      // Land on Feed so the fresh post is right there.
      ref.read(selectedTabProvider.notifier).set(1);
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      debugPrint('SONDR create post error: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Couldn’t create the post. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      widget.preview,
                      const SizedBox(height: 20),
                      TextField(
                        controller: _caption,
                        maxLines: 3,
                        minLines: 1,
                        maxLength: 200,
                        textCapitalization: TextCapitalization.sentences,
                        // Return puts the keyboard away rather than adding a
                        // line. The field still SOFT-wraps to its three lines
                        // as the text runs on; what it no longer does is take
                        // a hard newline from the key — a caption is a
                        // sentence, and the key you reach for to finish
                        // typing should finish typing.
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        style: theme.textTheme.bodyLarge,
                        decoration: InputDecoration(
                          hintText: 'Add a caption (optional)',
                          hintStyle: theme.textTheme.bodyLarge?.copyWith(
                            color: tokens.textTertiary,
                          ),
                          filled: true,
                          fillColor: tokens.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null) ...[
                SondrError(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
              ],
              // Above Share, as asked. NOTE this puts the supporting action
              // ON TOP of the primary, which inverts every other pair in the
              // app (delete-blur, the guest landing, keep/retake all lead
              // with the white one). Swapping the two lines flips it back.
              Center(
                child: SondrAction(
                  label: widget.hasPhoto ? 'Keep' : 'Not now',
                  supporting: true,
                  onPressed: _busy ? null : _exit,
                ),
              ),
              SharePrimaryButton(
                label: widget.submitLabel,
                busyLabel: widget.submitBusyLabel,
                busy: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The share flows' primary action.
///
/// Plain text, like every other primary in the app (Create account, Post).
/// It was a filled white pill — "white as text and never a fill" is the rule
/// it broke, and unlike the Apple button there is no compliance reason to
/// keep a capsule.
class SharePrimaryButton extends StatelessWidget {
  const SharePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busyLabel = 'Working…',
    this.busy = false,
  });

  final String label;

  /// What the button says mid-write — "Sharing…" to [label]'s "Share".
  final String busyLabel;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    // The action keeps its place; only the word and the tone change. Nulling
    // onPressed here (not just at the call site) means busy ALWAYS renders
    // the disabled tertiary tone and cannot be double-submitted.
    return Center(
      child: SondrAction(
        label: busy ? busyLabel : label,
        onPressed: busy ? null : onPressed,
      ),
    );
  }
}
