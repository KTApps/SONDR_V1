import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_field.dart';
import '../../shared/sondr_header.dart';
import 'profile_repository.dart';

/// Pick a unique handle. Validates format client-side, then claims it
/// atomically via [ProfileRepository.claimHandle] (rejecting duplicates).
class HandleScreen extends ConsumerStatefulWidget {
  const HandleScreen({super.key, this.suggestedDisplayName});

  /// Pre-fills the profile display name (e.g. the name Apple returned on first
  /// sign-in). The handle itself is always chosen by the user.
  final String? suggestedDisplayName;

  @override
  ConsumerState<HandleScreen> createState() => _HandleScreenState();
}

class _HandleScreenState extends ConsumerState<HandleScreen> {
  final _handle = TextEditingController();
  bool _busy = false;
  String? _error;

  static final _format = RegExp(r'^[a-z0-9_]{3,20}$');

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final handle = _handle.text.trim().toLowerCase();
    if (!_format.hasMatch(handle)) {
      setState(() => _error =
          '3–20 characters: lowercase letters, numbers, underscores.');
      return;
    }
    final uid = ref.read(currentUidProvider);
    final repo = ref.read(profileRepositoryProvider);
    if (uid == null || repo == null) {
      setState(() => _error = 'Not signed in.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.claimHandle(
        uid: uid,
        handle: handle,
        displayName: widget.suggestedDisplayName,
      );
      ref.invalidate(currentProfileProvider);
      // Land on Home (the timer) after finishing sign-up + handle setup.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on HandleTakenException {
      setState(() => _error = 'That handle is taken. Try another.');
    } catch (_) {
      setState(() => _error = 'Could not claim that handle. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    return Scaffold(
      body: SafeArea(
        // Scrolls for the keyboard — it did not before, so with the keyboard
        // up the field and its action had nowhere to go.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24 * scale,
            kSpacingBase * scale,
            24 * scale,
            kSpacingSection * scale,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SondrHeader(title: 'Choose a handle'),
              SizedBox(height: kSpacingBase * scale),
              Text(
                'This is how friends will find you. It can\'t be changed later.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13 * scale,
                  color: tokens.textSecondary,
                ),
              ),
              SizedBox(height: kSpacingBase * scale),
              SondrField(
                label: 'Handle',
                controller: _handle,
                enabled: !_busy,
                autocorrect: false,
                prefix: '@',
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              if (_error != null) ...[
                SizedBox(height: kSpacingBase * scale),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13 * scale,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
              // Declared gap is the tier minus SondrAction's own 12 padding.
              SizedBox(height: kSpacingBase * scale),
              // In flight, the action STAYS — same widget, same height, same
              // place — and says what it is doing, exactly as Create account
              // does. A spinner here replaced 45pt of action with 20pt of
              // glyph and lifted everything below it.
              Center(
                child: SondrAction(
                  label: _busy ? 'Claiming…' : 'Claim handle',
                  onPressed: _busy ? null : _submit,
                ),
              ),
              // Leaving is an exit: supporting grey, last in the action
              // stack, the same "Back" Friends and Blocked use. Not pinned —
              // this screen scrolls, so there is no footer to pin it to.
              //
              // Only when there is something to go back TO. After sign-up this screen
              // REPLACES the auth screen, so nothing is beneath it and no Back
              // appears — a brand-new account has to choose a handle. Pushed
              // from Profile or the friends gate, there is, and it does.
              if (Navigator.of(context).canPop())
                Center(
                  child: SondrAction(
                    label: 'Back',
                    supporting: true,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
