import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_field.dart';
import '../../shared/sondr_header.dart';
import '../../shared/sondr_swipe_row.dart';
import '../auth/handle_screen.dart';
import '../auth/profile_repository.dart';
import 'friends_repository.dart';
import 'models/friendship.dart';

/// Friends hub, reached from the Profile tab. Incoming requests to accept or
/// decline, the accepted friends list, and pending outgoing requests, plus a
/// handle field that sends a request when submitted.
///
/// Which actions are visible is deliberate: an action that IS the row's
/// purpose stays on the row, and management actions hide behind a swipe. A
/// request is a decision, so Accept and Decline are both visible; removing or
/// blocking a friend is rare, so it is summoned.
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

  Future<void> _add([String? handle]) async {
    final h = handle ?? _handle.text;
    await _run((repo) => repo.sendRequest(h), success: 'Request sent.');
    _handle.clear();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final hasHandle =
        profile.value != null && profile.value!.username.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: hasHandle ? _list() : const _HandleGate(),
      ),
    );
  }

  Widget _list() {
    final uid = ref.watch(currentUidProvider);
    final incoming = ref.watch(incomingRequestsProvider);
    final friends = ref.watch(friendsProvider);
    final outgoing = ref.watch(outgoingRequestsProvider);
    final scale = figmaScale(context);

    return ListView(
      padding: EdgeInsets.only(bottom: kSpacingSection * scale),
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SondrHeader(title: 'Friends'),
              SizedBox(height: kSpacingSection * scale),
              SondrField(
                label: 'Add by handle',
                controller: _handle,
                enabled: !_busy,
                autocorrect: false,
                prefix: '@',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _add(),
              ),
            ],
          ),
        ),
        SizedBox(height: kSpacingSection * scale),

        if (incoming.isNotEmpty) ...[
          _SectionHeader('${incoming.length} '
              '${incoming.length == 1 ? 'Request' : 'Requests'}'),
          for (final f in incoming)
            // A request is a decision, so both answers stay on the row.
            // Accept leads; Decline is the grey one among whites, which is
            // what makes it read as secondary rather than disabled.
            _FriendRow(
              identity: f.otherIdentity(uid ?? ''),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SondrAction(
                    label: 'Accept',
                    onPressed: _busy
                        ? null
                        : () => _run((r) => r.accept(f.id),
                            success: 'You\u2019re now friends.'),
                  ),
                  SondrAction(
                    label: 'Decline',
                    supporting: true,
                    onPressed:
                        _busy ? null : () => _run((r) => r.remove(f.id)),
                  ),
                ],
              ),
            ),
          SizedBox(height: kSpacingSection * scale),
        ],

        _SectionHeader('${friends.length} '
            '${friends.length == 1 ? 'Friend' : 'Friends'}'),
        for (final f in friends)
          SondrSwipeRow(
            // Most severe last: Block sits outermost.
            actions: [
              SondrAction(
                label: 'Remove',
                onPressed: _busy ? null : () => _run((r) => r.remove(f.id)),
              ),
              SondrAction(
                label: 'Block',
                onPressed: _busy ? null : () => _run((r) => r.remove(f.id)),
              ),
            ],
            child: _FriendRow(identity: f.otherIdentity(uid ?? '')),
          ),

        if (outgoing.isNotEmpty) ...[
          SizedBox(height: kSpacingSection * scale),
          _SectionHeader('${outgoing.length} Pending'),
          for (final f in outgoing)
            // Withdrawing is management, not the row's purpose, so it is
            // summoned by the swipe like Remove and Block.
            SondrSwipeRow(
              actions: [
                SondrAction(
                  label: 'Cancel',
                  onPressed: _busy ? null : () => _run((r) => r.remove(f.id)),
                ),
              ],
              child: _FriendRow(
                identity: f.otherIdentity(uid ?? ''),
                status: 'Requested',
              ),
            ),
        ],
      ],
    );
  }
}

/// One person in a list: a placeholder photo square and their username.
///
/// No "@" — the handle IS the name here. There is no photo in the data model
/// yet, so the square is a surface-toned placeholder rather than an avatar; it
/// is deliberately a rounded square, not a circle, and never a white fill.
class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.identity, this.status, this.trailing});

  final FriendIdentity? identity;

  /// Metadata beside the name, e.g. "Requested".
  final String? status;

  /// An affirmative action that stays visible, e.g. Accept. Destructive ones
  /// live behind the swipe instead.
  final Widget? trailing;

  static const double photo = 36;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final name = identity?.username ?? 'Unknown';

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 24 * scale,
        vertical: kSpacingPair * scale,
      ),
      child: Row(
        children: [
          Container(
            width: photo * scale,
            height: photo * scale,
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(8 * scale),
            ),
          ),
          SizedBox(width: kSpacingBase * scale),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15 * scale,
                color: tokens.textPrimary,
              ),
            ),
          ),
          if (status != null)
            Text(
              status!,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                color: tokens.textTertiary,
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
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24 * scale,
        0,
        24 * scale,
        kSpacingBase * scale,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 15 * scale,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
      ),
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
    final scale = figmaScale(context);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24 * scale),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Set a handle first',
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 20 * scale,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          SizedBox(height: kSpacingBase * scale),
          Text(
            'Friends find you by your handle.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13 * scale,
              color: tokens.textSecondary,
            ),
          ),
          SizedBox(height: kSpacingBase * scale),
          Center(
            child: SondrAction(
              label: 'Choose a handle',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HandleScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
