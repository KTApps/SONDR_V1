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
    this.submitLabel = 'Create',
    this.submitBusyLabel = 'Creating…',
  });

  final Widget preview;
  final String submitLabel;
  final String submitBusyLabel;

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
