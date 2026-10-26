import 'package:firebase_core/firebase_core.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../links/invite_link.dart';
import '../../shared/sondr_error.dart';
import '../../shared/sondr_field.dart';
import '../../shared/sondr_swipe_row.dart';
import '../auth/handle_screen.dart';
import '../profile/other_profile_screen.dart';
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

  /// Focus on the handle field means the keyboard is up and the page has
  /// roughly half its height. The footer sheds everything but Invite while
  /// that lasts, so the results have the room instead.
  final _handleFocus = FocusNode();
  bool _searching = false;
  bool _busy = false;

  /// Which request section is open, if any. At most one: opening Requests
  /// closes Pending and the other way round, as TTM does. Friends is not in
  /// this at all — it is always shown.
  _OpenSection _open = _OpenSection.none;

  /// Live handle search. [_matchesFor] is the query [_matches] answer, so an
  /// empty result only shows once a search for the CURRENT text has landed —
  /// otherwise every keystroke would flash "No one found".
  Timer? _debounce;
  String _query = '';
  String _matchesFor = '';
  List<HandleMatch> _matches = const [];

  void _onQueryChanged(String raw) {
    final q = normalizeHandle(raw);
    if (q == _query) return;
    setState(() => _query = q);
    _syncSearching();
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
    List<HandleMatch> found;
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
  void initState() {
    super.initState();
    _handleFocus.addListener(_syncSearching);
  }

  /// The results take over the page while there is something TYPED in a
  /// focused field — not on focus alone. The field opens focused now, and
  /// a page that swapped its sections for an empty results list the moment
  /// it appeared would have moved everything for nothing.
  void _syncSearching() {
    final want = _handleFocus.hasFocus && _query.isNotEmpty;
    if (want != _searching) setState(() => _searching = want);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _handleFocus.dispose();
    _handle.dispose();
    super.dispose();
  }

  /// The screen's one notice line, shown above the pinned actions.
  ///
  /// Replaces a SnackBar: it sits on the screen that produced it, in the
  /// app's own tones, and stays until the next action or keystroke rather
  /// than timing out. Failures take the error style; confirmations stay
  /// quiet — a success should not shout.
  String? _notice;
  bool _noticeIsError = true;

  void _say(String message, {bool isError = true}) {
    if (!mounted) return;
    setState(() {
      _notice = message;
      _noticeIsError = isError;
    });
  }

  Future<void> _run(Future<void> Function(FriendsRepository repo) action,
      {String? success}) async {
    final repo = ref.read(friendsRepositoryProvider);
    if (repo == null) {
      _say('Sign in to manage friends.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action(repo);
      if (success != null) _say(success, isError: false);
    } on FriendException catch (e) {
      _say(e.message);
    } on FirebaseException catch (e) {
      debugPrint('SONDR friends firebase error: ${e.code} :: ${e.message}');
      _say('Something went wrong. Please try again.');
    } catch (e) {
      debugPrint('SONDR friends error: $e');
      _say('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add([String? handle]) async {
    final h = handle ?? _handle.text;
    // No notice: the button has already flipped to Requested and the request
    // is already under Pending, so a third announcement said nothing new.
    await _run((repo) => repo.sendRequest(h));
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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        for (final m in _matches)
          _FriendRow(
            identity: FriendIdentity(username: m.handle, displayName: ''),
            // The row itself is the way to their profile; Add stays where it
            // is, so a tap on the name and a tap on the action still mean
            // two different things.
            onTap: () => openProfile(context, ref, m.uid, handle: m.handle),
            status: areFriends.contains(m.handle)
                ? 'Friends'
                : sent.contains(m.handle)
                    ? 'Requested'
                    : received.contains(m.handle)
                        ? 'Sent you a request'
                        : null,
            trailing: areFriends.contains(m.handle) ||
                    sent.contains(m.handle) ||
                    received.contains(m.handle)
                ? null
                : SondrAction(
                    label: 'Add',
                    fontSize: kRowActionSize,
                    onPressed: _busy ? null : () => _add(m.handle),
                  ),
          ),
      ],
    );
  }

  /// What the invite says.
  ///
  /// It carries this account's own link, so whoever follows it lands on a
  /// page naming the person who sent it and the app can credit them. With
  /// no handle claimed there is nobody to credit, and it points at the
  /// site itself — see [inviteUrlFor].
  String _inviteText() => inviteText(
    ref.read(currentProfileProvider).value?.username ?? '',
  );

  Future<void> _invite() async {
    // The OS share sheet, so the invite can go wherever the person
    // already talks to their friends. Copying to the clipboard made them
    // find somewhere to paste it.
    //
    // The sheet needs an anchor on iPad; on a phone it is ignored, and
    // the button's own rectangle is the honest one to give it.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: _inviteText(),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
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
                'Add friends',
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
                focusNode: _handleFocus,
                enabled: !_busy,
                autocorrect: false,
                filled: false,
                centered: true,
                textInputAction: TextInputAction.done,
                // Open ready to type, cursor in the field.
                autofocus: true,
                hint: 'Their handle',
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
                    onTap: () => _openOther(context, ref, f, uid),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SondrAction(
                          label: 'Accept',
                          fontSize: kRowActionSize,
                          // No notice: the row leaves Requests and joins
                          // Friends, and the profile's status reads
                          // Friends. Saying it a third time said nothing.
                          onPressed:
                              _busy ? null : () => _run((r) => r.accept(f.id)),
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
                      onTap: () => _openOther(context, ref, f, uid),
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  child: _FriendRow(
                    identity: f.otherIdentity(uid ?? ''),
                    onTap: () => _openOther(context, ref, f, uid),
                  ),
                ),
            ],
          ),
        ),

        ],

        // Pinned to the bottom, above the tab bar — never scrolls with the
        // list, as in TTM.
        if (_notice != null) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24 * scale),
            child: _noticeIsError
                ? SondrError(_notice!, textAlign: TextAlign.center)
                : Text(
                    _notice!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13 * scale,
                      color: tokens.textSecondary,
                    ),
                  ),
          ),
          SizedBox(height: kSpacingBase * scale),
        ],
        SizedBox(height: _kInviteTopGap * scale),
        Center(
          child: SondrAction(
            label: 'Invite your friends to sondr',
            onPressed: _invite,
          ),
        ),
        // Blocking is rare, so this is invisible until there is something to
        // undo — but undoing it has to be possible from somewhere, and
        // Friends is where the blocking happened. Supporting tone: it sits
        // with Back, below the one white action on the screen.
        if (!_searching &&
            (ref.watch(blockedAccountsProvider).value?.isNotEmpty ?? false))
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
        // Hidden while searching: with the keyboard up, Invite is the only
        // footer action worth the space.
        if (!_searching)
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

/// The other participant's profile, told the identity the friendship has
/// already denormalised — so it opens with their name in it whether or not
/// they have published a profile of their own.
void _openOther(
  BuildContext context,
  WidgetRef ref,
  Friendship f,
  String? myUid,
) {
  final me = myUid ?? '';
  final identity = f.otherIdentity(me);
  openProfile(
    context,
    ref,
    f.otherUid(me),
    handle: identity?.username ?? '',
    displayName: identity?.displayName ?? '',
  );
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
  const _FriendRow({
    required this.identity,
    this.status,
    this.trailing,
    this.onTap,
  });

  final FriendIdentity? identity;

  /// Their profile. Absent only where there is no uid to open.
  final VoidCallback? onTap;

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

    final row = Padding(
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
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // A tap on an OPEN swipe tray closes it; the row's own tap only means
      // "go to their profile" once nothing is revealed.
      onTap: onTap,
      child: row,
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
