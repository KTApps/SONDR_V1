import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import '../../shared/sondr_field.dart';
import '../../shared/sondr_header.dart';
import '../friends/friends_repository.dart';
import 'handle_screen.dart' show kHandlePrompt;
import '../links/invite_link.dart';
import '../links/invite_link_listener.dart'
    show handleLookupProvider, kHandleNotFound;

/// What this screen says when the handle is the asker's own.
const String kThatsYou = "That's you.";

/// Asked once, of a brand-new account, straight after it has claimed a
/// handle.
///
/// Never from the Profile tab's handle path and never again afterwards:
/// "who invited you" has one true answer and it is true on the day the
/// account is made. An account arriving on a device that followed an
/// invite link already knows the answer — the handle is waiting in
/// [PendingInviter] — and the field is filled in with it.
///
/// The layout is the handle screen's, element for element, because it is
/// the same moment in the same flow and anything else would read as a
/// different app: the hidden header holding its space, the prompt, the
/// field, the error under it, the primary action, and the supporting one
/// beneath that — Skip, where the handle screen puts Back.
class InvitedScreen extends ConsumerStatefulWidget {
  const InvitedScreen({super.key});

  @override
  ConsumerState<InvitedScreen> createState() => _InvitedScreenState();
}

class _InvitedScreenState extends ConsumerState<InvitedScreen> {
  final _handle = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Filled in from the link they followed, if they followed one.
    ref.read(pendingInviterProvider).read().then((held) {
      if (held != null && mounted && _handle.text.isEmpty) {
        setState(() => _handle.text = held);
      }
    });
  }

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  /// Done with the question, however it was answered.
  Future<void> _leave() async {
    await ref.read(pendingInviterProvider).clear();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _submit() async {
    final handle = _handle.text.trim().toLowerCase();
    if (!kHandleFormat.hasMatch(handle)) {
      setState(() => _error = kHandleNotFound);
      return;
    }
    final uid = ref.read(currentUidProvider);
    final repo = ref.read(friendsRepositoryProvider);
    final lookup = ref.read(handleLookupProvider);
    if (uid == null || repo == null || lookup == null) {
      setState(() => _error = kInviteFailed);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final theirUid = await lookup.uidFor(handle);
      if (theirUid == null) {
        setState(() => _error = kHandleNotFound);
        return;
      }
      if (theirUid == uid) {
        setState(() => _error = kThatsYou);
        return;
      }
      await repo.recordInvite(inviterUid: theirUid, inviterHandle: handle);
      await _leave();
    } on FriendException catch (e) {
      // The invite could not be written, or the request could not. Either
      // way the batch landed whole or not at all.
      debugPrint('SONDR invite failed: ${e.message}');
      setState(() => _error = kInviteFailed);
    } catch (e) {
      debugPrint('SONDR invite failed: ${e.runtimeType}');
      setState(() => _error = kInviteFailed);
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
              // Holding the space a header would take, exactly as the
              // handle screen does — the two screens are one moment and
              // nothing may shift between them.
              const Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: SondrHeader(title: 'Who invited you?'),
              ),
              SizedBox(height: kSpacingBase * scale),
              // The question, in the space the handle screen's own line
              // takes. That line runs to two at every text size and this
              // one to one, and an invisible copy of it holds the
              // difference — so the field and both actions land exactly
              // where they did a moment ago. The same maintained-size
              // trick the header above uses, for the same reason.
              Stack(
                children: [
                  Visibility(
                    visible: false,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Text(
                      kHandlePrompt,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13 * scale,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    'Who invited you?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13 * scale,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: kSpacingBase * scale),
              SondrField(
                label: 'Their handle',
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
                SondrError(_error!),
              ],
              SizedBox(height: kSpacingBase * scale),
              Center(
                child: SondrAction(
                  label: _busy ? 'Sending…' : 'Continue',
                  onPressed: _busy ? null : _submit,
                ),
              ),
              // Where the handle screen puts Back. Nobody has to answer
              // this, and an account is not worth less for arriving on its
              // own.
              Center(
                child: SondrAction(
                  label: 'Skip',
                  supporting: true,
                  onPressed: _busy ? null : _leave,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What it says when the write did not go through.
const String kInviteFailed = "Couldn't save that. Try again.";
