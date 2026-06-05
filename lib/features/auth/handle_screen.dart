import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Choose a handle'),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'This is how friends will find you. It can\'t be changed later.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _handle,
                enabled: !_busy,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                onSubmitted: (_) => _busy ? null : _submit(),
                decoration: const InputDecoration(
                  prefixText: '@',
                  labelText: 'Handle',
                  hintText: 'e.g. tanaka',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.ringFillOuter,
                  foregroundColor: tokens.background,
                  disabledBackgroundColor: tokens.ringTrack,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: theme.textTheme.labelLarge,
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Claim handle'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
