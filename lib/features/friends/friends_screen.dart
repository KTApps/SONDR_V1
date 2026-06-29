import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../auth/handle_screen.dart';
import '../auth/profile_repository.dart';
import 'friends_repository.dart';
import 'models/friendship.dart';

/// Friends hub, reached from the Profile tab. Incoming requests to accept or
/// decline, the accepted friends list, and pending outgoing requests — plus an
/// add-by-handle field. Friends-only, so the only way in is the exact handle.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _handle = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function(FriendsRepository repo) action,
      {String? success}) async {
    final repo = ref.read(friendsRepositoryProvider);
    if (repo == null) {
      _toast('Sign in to manage friends.');
      return;
    }
    setState(() => _busy = true);
    try {
      await action(repo);
      if (success != null) _toast(success);
    } on FriendException catch (e) {
      _toast(e.message);
    } on FirebaseException catch (e) {
      debugPrint('SONDR friends firebase error: ${e.code} :: ${e.message}');
      _toast('Something went wrong. Please try again.');
    } catch (e) {
      debugPrint('SONDR friends error: $e');
      _toast('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final handle = _handle.text;
    await _run((repo) => repo.sendRequest(handle), success: 'Request sent.');
    _handle.clear();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final hasHandle =
        profile.value != null && profile.value!.username.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        iconTheme: const IconThemeData(size: 20),
        // Title removed; explicit left-aligned back chevron (calendar pattern).
        leadingWidth: 44,
        leading: IconButton(
          padding: const EdgeInsets.only(left: 22),
          alignment: Alignment.centerLeft,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: hasHandle ? _list() : const _HandleGate(),
      ),
    );
  }

  Widget _list() {
    final uid = ref.watch(currentUidProvider);
    final incoming = ref.watch(incomingRequestsProvider);
    final friends = ref.watch(friendsProvider);
    final outgoing = ref.watch(outgoingRequestsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        _AddByHandle(controller: _handle, busy: _busy, onAdd: _add),
        const SizedBox(height: 28),
        if (incoming.isNotEmpty) ...[
          _SectionHeader('Requests (${incoming.length})'),
          for (final f in incoming)
            _FriendTile(
              identity: f.otherIdentity(uid ?? ''),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run((r) => r.accept(f.id),
                            success: 'You’re now friends.'),
                    child: const Text('Accept'),
                  ),
                  IconButton(
                    tooltip: 'Decline',
                    onPressed: _busy ? null : () => _run((r) => r.remove(f.id)),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
        _SectionHeader('Friends (${friends.length})'),
        if (friends.isEmpty)
          const _Hint('No friends yet. Add someone by their handle above.')
        else
          for (final f in friends)
            _FriendTile(
              identity: f.otherIdentity(uid ?? ''),
              trailing: IconButton(
                tooltip: 'Remove',
                onPressed: _busy ? null : () => _run((r) => r.remove(f.id)),
                icon: const Icon(Icons.person_remove_outlined),
              ),
            ),
        if (outgoing.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SectionHeader('Pending (${outgoing.length})'),
          for (final f in outgoing)
            _FriendTile(
              identity: f.otherIdentity(uid ?? ''),
              subtitle: 'Requested',
              trailing: TextButton(
                onPressed: _busy ? null : () => _run((r) => r.remove(f.id)),
                child: const Text('Cancel'),
              ),
            ),
        ],
      ],
    );
  }
}

class _AddByHandle extends StatelessWidget {
  const _AddByHandle({
    required this.controller,
    required this.busy,
    required this.onAdd,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !busy,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            style: theme.textTheme.bodyLarge,
            cursorColor: tokens.textPrimary,
            onSubmitted: (_) => busy ? null : onAdd(),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              // No box / fill / underline — floats on the background.
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              // Muted always-visible placeholder; signals it's a handle field.
              hintText: '@handle',
              hintStyle: theme.textTheme.bodyLarge
                  ?.copyWith(color: tokens.textTertiary),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // "Add" as a quiet text action (was a solid white FilledButton).
        TextButton(
          onPressed: busy ? null : onAdd,
          style: TextButton.styleFrom(foregroundColor: tokens.textSecondary),
          child: busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({required this.identity, this.subtitle, this.trailing});

  final FriendIdentity? identity;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final label = identity?.label ?? 'Unknown';
    final handle = identity?.username ?? '';
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: tokens.surface,
            child: Text(initial,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: tokens.textPrimary)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge),
                Text(
                  subtitle ?? (handle.isEmpty ? '' : '@$handle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tokens.textTertiary),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
      );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: tokens.textSecondary)),
    );
  }
}

/// Shown when the user has no handle yet — you must be findable to have friends.
class _HandleGate extends StatelessWidget {
  const _HandleGate();

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Set a handle first',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Friends find you by your handle, so you’ll need one before you can '
            'add friends or receive requests.',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const HandleScreen(),
            )),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.ringFillOuter,
              foregroundColor: tokens.background,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Choose a handle'),
          ),
        ],
      ),
    );
  }
}
