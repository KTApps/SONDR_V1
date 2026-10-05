import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_header.dart';
import 'friends_repository.dart';
import 'models/block.dart';

/// The people this user has blocked, and the only way to undo it.
///
/// Blocking is otherwise irreversible from inside the app, so this screen is
/// not optional. It is deliberately quiet — reached from Profile, never
/// surfaced in the Friends flow, and empty for almost everyone.
class BlockedAccountsScreen extends ConsumerStatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  ConsumerState<BlockedAccountsScreen> createState() =>
      _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState
    extends ConsumerState<BlockedAccountsScreen> {
  bool _busy = false;

  Future<void> _unblock(Block block) async {
    final repo = ref.read(friendsRepositoryProvider);
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      await repo.unblockUser(block.blocked);
    } catch (e) {
      debugPrint('SONDR unblock error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(content: Text('Couldn’t unblock. Try again.')),
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final blocked = ref.watch(blockedAccountsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * scale),
              child: const SondrHeader(title: 'Blocked'),
            ),
            SizedBox(height: kSpacingSection * scale),
            Expanded(
              child: blocked.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => _note(context, 'Couldn’t load blocked accounts.'),
                data: (list) {
                  if (list.isEmpty) return _note(context, 'No one blocked.');
                  return ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final b in list)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24 * scale,
                            vertical: kSpacingBase * scale,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: kAvatarList * scale,
                                height: kAvatarList * scale,
                                decoration: BoxDecoration(
                                  color: tokens.surface,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: kSpacingBase * scale),
                              Expanded(
                                child: Text(
                                  b.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 15 * scale,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                              ),
                              SondrAction(
                                label: 'Unblock',
                                onPressed: _busy ? null : () => _unblock(b),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(BuildContext context, String text) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24 * scale),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 13 * scale,
              color: tokens.textSecondary,
            ),
      ),
    );
  }
}
