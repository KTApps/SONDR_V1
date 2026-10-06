import 'package:firebase_core/firebase_core.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_field.dart';
import '../../shared/sondr_swipe_row.dart';
import '../auth/handle_screen.dart';
import '../auth/profile_repository.dart';
import 'blocked_accounts_screen.dart';
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

  /// Which request section is open, if any. At most one: opening Requests
  /// closes Pending and the other way round, as TTM does. Friends is not in
  /// this at all — it is always shown.
  _OpenSection _open = _OpenSection.none;

  /// Copy-link feedback for the invite action, cleared after a moment.
  bool _copied = false;

  /// Live handle search. [_matchesFor] is the query [_matches] answer, so an
  /// empty result only shows once a search for the CURRENT text has landed —
  /// otherwise every keystroke would flash "No one found".
  Timer? _debounce;
  String _query = '';
  String _matchesFor = '';
  List<String> _matches = const [];

  void _onQueryChanged(String raw) {
    final q = normalizeHandle(raw);
    if (q == _query) return;
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() {
        _matches = const [];
        _matchesFor = '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

  Future<void> _search(String q) async {
    final repo = ref.read(friendsRepositoryProvider);
    if (repo == null) return;
    List<String> found;
    try {
      found = await repo.searchHandles(q);
    } catch (e) {
      debugPrint('SONDR handle search error: $e');
      found = const [];
    }
    // Drop stale answers if the user kept typing.
    if (!mounted || q != _query) return;
    setState(() {
      _matches = found;
      _matchesFor = q;
    });
  }

  void _toggle(_OpenSection section) => setState(
        () => _open = _open == section ? _OpenSection.none : section,
      );

  @override
  void dispose() {
    _debounce?.cancel();
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
    _onQueryChanged('');
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

  /// Matching handles, each showing where that person already stands with
  /// you — TTM's Add / Requested / Friends states — so tapping Add is only
  /// offered where it means something.
  Widget _results(
    String uid,
    List<Friendship> incoming,
    List<Friendship> friends,
    List<Friendship> outgoing,
  ) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    // An empty answer only counts once the search for THIS text has landed.
    if (_matchesFor != _query) return const SizedBox.shrink();
    if (_matches.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24 * scale,
          vertical: _kRowPad * scale,
        ),
        child: Text(
          'No one found',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13 * scale,
            color: tokens.textSecondary,
          ),
        ),
      );
    }

    Set<String> handlesOf(List<Friendship> list) =>
        {for (final f in list) f.otherIdentity(uid)?.username ?? ''};
    final areFriends = handlesOf(friends);
    final sent = handlesOf(outgoing);
    final received = handlesOf(incoming);

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final h in _matches)
          _FriendRow(
            identity: FriendIdentity(username: h, displayName: ''),
            status: areFriends.contains(h)
                ? 'Friends'
                : sent.contains(h)
                    ? 'Requested'
                    : received.contains(h)
                        ? 'Sent you a request'
                        : null,
            trailing: areFriends.contains(h) ||
                    sent.contains(h) ||
                    received.contains(h)
                ? null
                : SondrAction(
                    label: 'Add',
                    fontSize: kRowActionSize,
                    onPressed: _busy ? null : () => _add(h),
                  ),
          ),
      ],
    );
  }

  Future<void> _invite() async {
    // No OS share sheet in this app and no package for one, so the link goes
    // to the clipboard with a confirmation instead.
    await Clipboard.setData(
      const ClipboardData(
        text: 'Join me on Sondr — https://testflight.apple.com/join/XgqKWR4E',
      ),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Widget _list() {
    final uid = ref.watch(currentUidProvider);
    final incoming = ref.watch(incomingRequestsProvider);
    final friends = ref.watch(friendsProvider);
    final outgoing = ref.watch(outgoingRequestsProvider);
    final scale = figmaScale(context);
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: _kTopRhythm * scale),
              Text(
                'Add Friends',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              SizedBox(height: _kTopRhythm * scale),
              // Invisible until typed in: the heading above already says what
              // this takes, so the capsule would only add furniture.
              SondrField(
                controller: _handle,
                enabled: !_busy,
                autocorrect: false,
                filled: false,
                centered: true,
                textInputAction: TextInputAction.done,
                onChanged: _onQueryChanged,
                // Adding is by tapping a result, so Enter only puts the
                // keyboard away.
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
              ),
            ],
          ),
        ),
        // The header brings its own 12 above its text, so this makes up the
        // rest of the rhythm rather than adding to it.
        SizedBox(height: (_kTopRhythm - _kHeaderPad) * scale),

        // While there is something in the field the results take over the
        // page, as TTM does. Clearing it brings the sections back.
        if (_query.isNotEmpty) ...[
          Expanded(child: _results(uid ?? '', incoming, friends, outgoing)),
        ] else ...[

        // Requests — collapsed by default; the count alone is the summary.
        if (incoming.isNotEmpty) ...[
          _SectionHeader(
            '${incoming.length} '
            '${incoming.length == 1 ? 'Request' : 'Requests'}',
            onTap: () => _toggle(_OpenSection.requests),
          ),
          if (_open == _OpenSection.requests)
            _Capped(
              rows: _kShortRows,
              hasAction: true,
              children: [
                for (final f in incoming)
                  // A request is a decision, so both answers stay on the row.
                  _FriendRow(
                    identity: f.otherIdentity(uid ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SondrAction(
                          label: 'Accept',
                          fontSize: kRowActionSize,
                          onPressed: _busy
                              ? null
                              : () => _run((r) => r.accept(f.id),
                                  success: 'You\u2019re now friends.'),
                        ),
                        SondrAction(
                          label: 'Decline',
                          fontSize: kRowActionSize,
                          supporting: true,
                          onPressed:
                              _busy ? null : () => _run((r) => r.remove(f.id)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          SizedBox(height: _kSectionGap * scale),
        ],

        // Pending — collapsed by default, and never open beside Requests.
        if (outgoing.isNotEmpty) ...[
          _SectionHeader(
            '${outgoing.length} Pending',
            onTap: () => _toggle(_OpenSection.pending),
          ),
          if (_open == _OpenSection.pending)
            _Capped(
              rows: _kShortRows,
              children: [
                for (final f in outgoing)
                  SondrSwipeRow(
                    actions: [
                      SondrAction(
                        label: 'Cancel',
                        fontSize: kRowActionSize,
                        onPressed:
                            _busy ? null : () => _run((r) => r.remove(f.id)),
                      ),
                    ],
                    child: _FriendRow(
                      identity: f.otherIdentity(uid ?? ''),
                      status: 'Requested',
                    ),
                  ),
              ],
            ),
          SizedBox(height: _kSectionGap * scale),
        ],

        // Friends — always shown, and takes whatever height is left so the
        // list fills the page rather than stopping at a fixed row count.
        _SectionHeader('${friends.length} '
            '${friends.length == 1 ? 'Friend' : 'Friends'}'),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final f in friends)
                SondrSwipeRow(
                  // Most severe last: Block sits outermost.
                  actions: [
                    SondrAction(
                      label: 'Remove',
                      fontSize: kRowActionSize,
                      onPressed:
                          _busy ? null : () => _run((r) => r.remove(f.id)),
                    ),
                    SondrAction(
                      label: 'Block',
                      fontSize: kRowActionSize,
                      onPressed: _busy
                          ? null
                          : () {
                              final other = f.otherIdentity(uid ?? '');
                              _run(
                                (r) => r.blockUser(
                                  targetUid: f.otherUid(uid ?? ''),
                                  username: other?.username ?? '',
                                  displayName: other?.displayName ?? '',
                                ),
                                success: 'Blocked.',
                              );
                            },
                    ),
                  ],
                  child: _FriendRow(identity: f.otherIdentity(uid ?? '')),
                ),
            ],
          ),
        ),

        ],

        // Pinned to the bottom, above the tab bar — never scrolls with the
        // list, as in TTM.
        SizedBox(height: _kInviteTopGap * scale),
        Center(
          child: SondrAction(
            label: _copied ? 'Copied' : 'Invite your friends to Sondr',
            onPressed: _invite,
          ),
        ),
        // Blocking is rare, so this is invisible until there is something to
        // undo — but undoing it has to be possible from somewhere, and
        // Friends is where the blocking happened. Supporting tone: it sits
        // with Back, below the one white action on the screen.
        if (ref.watch(blockedAccountsProvider).value?.isNotEmpty ?? false)
          Center(
            child: SondrAction(
              label: 'Blocked accounts',
              supporting: true,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const BlockedAccountsScreen(),
                ),
              ),
            ),
          ),
        // Leaving is an exit, so it takes the supporting treatment and sits
        // last. This replaces the back chevron that used to head the screen.
        Center(
          child: SondrAction(
            label: 'Back',
            supporting: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        SizedBox(height: _kInviteGap * scale),
      ],
    );
  }
}

/// Which collapsible section is open. Friends is deliberately absent — it is
/// always shown, so it is not a state this can hold.
enum _OpenSection { none, requests, pending }

/// TTM's gap between sections (.padding(.top, 8)) — this screen follows TTM's
/// spacing rhythm even though the type is Sondr's.
const double _kSectionGap = 8;

/// TTM's vertical padding inside a section header (.padding(.vertical, 12)).
const double _kHeaderPad = 12;

/// Vertical padding on a row — half the gap between two rows, and the same
/// across Friends, Requests and Pending so the three lists read alike.
const double _kRowPad = 10;

/// Text-to-text distance from a section header to its first row, held
/// constant: the header's bottom padding makes up whatever the row's own
/// padding does not, so tightening the rows does not drag the header down
/// onto them.
const double _kHeaderToRow = 26;

/// Air below the pinned invite block, clearing the tab bar.
const double _kInviteGap = 24;

/// Air above it. Tighter than below — it only has to stop the last row from
/// reading as part of the invite, and the space it gives back is a whole
/// extra friend on screen.
const double _kInviteTopGap = 16;

/// One rhythm down the top block: top to heading, heading to the cursor, and
/// cursor to the first section header are all this far apart. Measured text to
/// text, so the gaps that follow subtract whatever padding sits between.
const double _kTopRhythm = 24;

/// Rows a collapsed-by-default section shows before scrolling.
const int _kShortRows = 3;

/// A list capped to [rows] rows, scrolling internally beyond that, so one long
/// section can never push the rest of the page off the screen.
class _Capped extends StatelessWidget {
  const _Capped({
    required this.rows,
    required this.children,
    this.hasAction = false,
  });

  final int rows;
  final List<Widget> children;

  /// Whether these rows carry a visible action, which makes them taller.
  final bool hasAction;

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);
    final rowHeight = _FriendRow.heightOf(hasAction: hasAction);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: rowHeight * rows * scale),
      child: ListView(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        children: children,
      ),
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

  /// A row action's MEASURED height — a row carrying one (Accept/Decline) is
  /// taller than a plain row, and the list caps have to know which they hold
  /// or the last visible row is clipped mid-way.
  ///
  /// 42 at [kRowActionSize]: 12 of tap padding either side plus the text's
  /// own line box. It was 45 while the actions were 15pt; shrinking them
  /// without re-measuring left every action row reserving 3pt it no longer
  /// used.
  static const double actionHeight = 42;

  static double heightOf({required bool hasAction}) =>
      (hasAction ? actionHeight : photo) + _kRowPad * 2;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final name = identity?.username ?? 'Unknown';

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 24 * scale,
        vertical: _kRowPad * scale,
      ),
      child: Row(
        children: [
          Container(
            width: photo * scale,
            height: photo * scale,
            decoration: BoxDecoration(
              color: tokens.surface,
              shape: BoxShape.circle,
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
                fontWeight: FontWeight.w700,
                color: tokens.textPrimary,
              ),
            ),
          ),
          if (status != null)
            Text(
              status!,
              style: theme.textTheme.bodyMedium?.copyWith(
                // The same size as the row actions it stands in for — this
                // label sits exactly where Accept/Decline would.
                fontSize: kRowActionSize * scale,
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

/// A section's count, and for the collapsible ones its tap target.
///
/// Plain text, not a capsule: a capsule in this app means "goes somewhere",
/// and these expand in place. The count is the whole summary when collapsed.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {this.onTap});

  final String text;

  /// Null for Friends, which is always shown and never collapses.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);

    final label = Padding(
      padding: EdgeInsets.fromLTRB(
        24 * scale,
        _kHeaderPad * scale,
        24 * scale,
        (_kHeaderToRow - _kRowPad) * scale,
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

    if (onTap == null) return label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: label,
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
