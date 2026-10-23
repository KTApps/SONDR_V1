import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/progress_ring.dart';
import '../../shared/ring/ring_metrics.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import '../../shared/sondr_notice.dart';
import '../../shared/sondr_prompt.dart';
import '../auth/guest_prompts.dart';
import '../feed/models/post.dart';
import '../feed/posts_repository.dart';
import '../feed/single_post_screen.dart';
import '../friends/friends_repository.dart';
import '../friends/models/friendship.dart';
import '../shell/main_shell.dart';
import '../timer/home_metrics.dart';
import '../reports/report.dart';
import '../reports/report_flow.dart';
import 'friend_status.dart';
import 'profile_action_bar.dart';
import 'profile_actions.dart';
import 'profile_metrics.dart';
import 'public_profile.dart';

/// Someone else's profile: the same page as my own, about them.
///
/// What it can show is what the rules allow. A stranger — and anyone who has
/// blocked me, which must look exactly the same — sees their initial, their
/// handle, their hours, and an invitation to add each other. A friend sees
/// their newest shared milestone photo in the ring, their hours and how many
/// milestones they have shared, and three sections: their friends, their
/// milestones, their posts.
///
/// Milestones here means milestones they have SHARED. Their real count is
/// their own business; a profile can only honestly show what they chose to
/// put in front of people, and that is a post.
class OtherProfileScreen extends ConsumerStatefulWidget {
  const OtherProfileScreen({
    super.key,
    required this.uid,
    this.handle = '',
    this.displayName = '',
  });

  final String uid;

  /// What the entry point already knew about them — a post's byline, a
  /// friendship's denormalised identity, a search result. Shown until (and
  /// unless) their published profile says otherwise, so a profile whose
  /// owner has published nothing is still somebody.
  final String handle;
  final String displayName;

  @override
  ConsumerState<OtherProfileScreen> createState() => _OtherProfileScreenState();
}

/// Their profile, pushed. My own page is a tab, not a push — so a row for
/// me (in their friends list, or a byline on my own post) switches to it
/// rather than opening a second copy of it.
void openProfile(
  BuildContext context,
  WidgetRef ref,
  String uid, {
  String handle = '',
  String displayName = '',
}) {
  if (uid.isEmpty) return;
  if (uid == ref.read(currentUidProvider)) {
    ref.read(selectedTabProvider.notifier).set(kProfileTabIndex);
    Navigator.of(context).popUntil((route) => route.isFirst);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OtherProfileScreen(
        uid: uid,
        handle: handle,
        displayName: displayName,
      ),
    ),
  );
}

/// Home · Feed · Profile.
const int kProfileTabIndex = 2;

class _OtherProfileScreenState extends ConsumerState<OtherProfileScreen> {
  String? _notice;

  /// Whether the line is a thank-you rather than a failure.
  bool _noticeIsQuiet = false;
  bool _busy = false;

  /// What the page shows while the write is in flight.
  ///
  /// Add and Accept answer at once — the slot empties, the line reads
  /// Requested or Friends — rather than waiting for the friendship to come
  /// back down the stream. Cleared when the stream catches up, and put
  /// back by the failure handler if it never does.
  FriendStatus? _pending;

  void _say(String message) {
    if (mounted) {
      setState(() {
        _notice = message;
        _noticeIsQuiet = false;
      });
    }
  }

  Future<void> _run(Future<void> Function(ProfileActions acts) action) async {
    final acts = ref.read(profileActionsProvider);
    if (acts == null) {
      _say('Sign in to add friends.');
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await action(acts);
    } on FriendException catch (e) {
      // Including the one a block raises, whose wording is identical to a
      // handle that does not exist. The optimistic answer goes back.
      _pending = null;
      _say(e.message);
    } catch (e) {
      debugPrint('SONDR profile action error: ${e.runtimeType}');
      _pending = null;
      _say('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    final myUid = ref.watch(currentUidProvider) ?? '';
    final friendships =
        ref.watch(friendshipsProvider).value ?? const <Friendship>[];
    final settled = friendStatusOf(
      myUid: myUid,
      theirUid: widget.uid,
      friendships: friendships,
      blockedUids: ref.watch(blockedUidsProvider),
    );
    // The optimistic answer, until the friendship itself says the same.
    if (_pending != null && _pending == settled) _pending = null;
    final status = _pending ?? settled;
    final sees = friendStatusSeesContent(status);

    final publicAsync = ref.watch(publicProfileProvider(widget.uid));
    final postsAsync = ref.watch(profilePostsProvider(widget.uid));
    final friendsAsync = ref.watch(friendUidsProvider(widget.uid));

    // One gate for the page: nothing is painted until everything it would
    // paint is known, so no section arrives a frame after the rest.
    final ready = publicAsync.hasValue &&
        (!sees || (postsAsync.hasValue && friendsAsync.hasValue));
    if (!ready) return Scaffold(backgroundColor: tokens.background);

    // Published first, then what the entry point handed us, then our
    // friendship's own copy. Only a page that was told nothing by anyone
    // has to say "Someone".
    final published = publicAsync.value;
    final them = profileIdentity(
      uid: widget.uid,
      published: published,
      handle: widget.handle,
      displayName: widget.displayName,
      fromFriendship: friendshipWith(
        myUid: myUid,
        theirUid: widget.uid,
        friendships: friendships,
      )?.profiles[widget.uid],
    );
    final posts = sees ? (postsAsync.value ?? const <Post>[]) : const <Post>[];
    final milestones = [
      for (final p in posts)
        if (p is MilestonePost) p,
    ];
    final friendCount = sees ? (friendsAsync.value ?? const <String>[]).length : 0;

    final strips = <String>[
      for (final p in milestones)
        if (p.photos.isNotEmpty) p.photos.first.url,
      for (final p in posts)
        if (p.photos.isNotEmpty) p.photos.first.url,
    ];
    if (strips.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) precachePhotos(context, strips);
      });
    }

    // Read above the SafeArea that consumes it, like the personal Profile.
    final topInset = MediaQuery.paddingOf(context).top;

    // What the Posts grid holds, and how it is laid out: four across,
    // filling the content box exactly.
    final pictured = [
      for (final p in posts)
        if (p.photos.isNotEmpty) p,
    ];
    final contentWidth =
        MediaQuery.sizeOf(context).width - 2 * kProfileGutter * scale;
    final tile = profileGridTile(context, contentWidth);
    final rows = <List<Post>>[
      for (var i = 0; i < pictured.length; i += kProfileGridColumns)
        pictured.sublist(
          i,
          (i + kProfileGridColumns).clamp(0, pictured.length),
        ),
    ];

    return Scaffold(
      // The bar sits where the tab bar sits, and takes the same space out
      // of the page, so the grid runs to its top edge exactly as Profile's
      // own content runs to the tab bar's.
      bottomNavigationBar: ProfileActionBar(
        slots: [
          // The friendship, as something to DO. Add and Accept act on the
          // tap; Remove asks first, as it did before it came down here.
          switch (friendActionLabel(status)) {
            final String label => ProfileBarSlot(
              label: label,
              onTap: _busy
                  ? null
                  : () => status == FriendStatus.accepted
                        ? _remove(them, friendships, myUid)
                        : _act(status, them, friendships, myUid),
            ),
            _ => null,
          },
          ProfileBarSlot(
            label: 'Back',
            onTap: () => Navigator.of(context).maybePop(),
          ),
          if (status == FriendStatus.blockedByMe)
            null
          else
            ProfileBarSlot(
              label: 'Block',
              onTap: _busy ? null : () => _blockOrReport(them, myUid),
            ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            // The pin exists to land what the first screen ends on where
            // the personal Profile's last element lands. A stranger's page
            // has nothing to reach that far, and pinning anyway is what
            // inflates a hero into a void — so it is top-anchored and
            // compact instead, exactly as a guest's own Profile is.
            final canPin = sees;
            final heroGap = [
              SizedBox(height: kProfileHeroGapMin * scale),
              Flexible(
                child: ProfileCappedSlack(
                  (kProfileHeroGapMax - kProfileHeroGapMin) * scale,
                ),
              ),
            ];
            // The first screen ends one ROW GAP after the grid's first
            // row, not one clearance, so the second row follows at the
            // grid's own rhythm. Both the box and its trailing space come
            // down by the same amount, which leaves the hero gaps — and so
            // every element above — exactly where they were.
            final clearance = profileLastStripClearance(context);
            final trailing = rows.isEmpty
                ? clearance
                : kProfileStripGap * scale;
            final pin = profileFirstScreenHeight(context, topInset) -
                (clearance - trailing);

            return SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileFirstScreen(
                    pin: pin,
                    // No viewport floor: the grid carries on straight out
                    // of the box, and the bar is what holds the bottom of
                    // the page now.
                    viewport: 0,
                    gapFloor: kProfileHeroGapMin * scale,
                    gapCeiling: kProfileHeroGapMax * scale,
                    gapUnpinned: kProfileHeroGap * scale,
                    canPin: canPin,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: kProfileTopMargin * scale),
                        ProfileGutter(
                          child: _Emblem(
                            them: them,
                            photoUrl: sees ? _ringPhoto(milestones) : null,
                            fill: sees,
                          ),
                        ),
                        // The two flexible gaps, either side of the
                        // handle-and-status pair — siblings in ONE column,
                        // because flex only equalises siblings.
                        ...heroGap,
                        ProfileGutter(
                          child: _HeroCaption(
                            them: them,
                            status: status,
                            busy: _busy,
                            onAct: () => _act(status, them, friendships, myUid),
                          ),
                        ),
                        ...heroGap,
                        // Hours are the published copy's alone: a handle
                        // from a byline says nothing about how long they
                        // have worked, and 0 would be a claim.
                        if (published != null || sees) ...[
                          ProfileGutter(
                            child: _Stats(
                              hours: published?.wholeHours,
                              milestones: sees ? milestones.length : null,
                            ),
                          ),
                        ],
                        if (!sees) ...[
                          SizedBox(height: kSpacingBase * scale),
                          ProfileGutter(
                            child: Text(
                              'Add each other as friends to see posts and '
                              'milestones.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 13 * scale,
                                    color: tokens.textSecondary,
                                  ),
                            ),
                          ),
                        ],
                        if (_notice != null) ...[
                          SizedBox(height: kSpacingBase * scale),
                          ProfileGutter(
                            // A thank-you is not an error, and the page
                            // has one tone for each: the quiet grey for
                            // "we have it", the error style for "we
                            // haven't".
                            child: _noticeIsQuiet
                                ? SondrNotice(
                                    _notice!,
                                    textAlign: TextAlign.center,
                                  )
                                : SondrError(
                                    _notice!,
                                    textAlign: TextAlign.center,
                                  ),
                          ),
                        ],
                        if (sees) ...[
                          _Break(
                            child: ProfileGutter(
                              child: ProfileHeading(
                                label: 'Friends',
                                count: friendCount > 0 ? '$friendCount' : null,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => FriendsOfScreen(
                                      uid: widget.uid,
                                      handle: them.handle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _Break(
                            child: _PostSection(
                              label: 'Milestones',
                              uid: widget.uid,
                              handle: them.handle,
                              posts: milestones,
                              milestonesOnly: true,
                            ),
                          ),
                          // Posts: the heading, and the grid's FIRST row.
                          // The rest of the grid is below, outside the
                          // box, so the page can be as long as it likes
                          // without moving anything above it.
                          _Break(
                            child: _PostsHead(
                              uid: widget.uid,
                              handle: them.handle,
                              count: posts.length,
                              firstRow: rows.isEmpty ? const [] : rows.first,
                              tile: tile,
                            ),
                          ),
                        ],
                        SizedBox(height: trailing),
                      ],
                    ),
                  ),
                  // THE REST OF THE GRID, straight out of the box at the
                  // same rhythm.
                  if (sees)
                    for (var r = 1; r < rows.length; r++) ...[
                      ProfileGutter(
                        child: _GridRow(photos: rows[r], tile: tile),
                      ),
                      if (r < rows.length - 1)
                        SizedBox(height: kProfileStripGap * scale),
                    ],
                  // The last row ends above the bar where Profile's own
                  // content ends above the tab bar.
                  SizedBox(height: kSpacingBase * scale),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// The status action, for the three states that do something.
  void _act(
    FriendStatus status,
    PublicProfile them,
    List<Friendship> friendships,
    String myUid,
  ) {
    switch (status) {
      case FriendStatus.none:
        // Friends and handles live on a permanent account.
        if (!requireAccount(
          context,
          ref,
          message:
              'Create an account to add friends. Your friends and progress '
              'stay safe if you change phones.',
        )) {
          return;
        }
        // By uid. The handle rides along for the wording and for the
        // pending row to print; it is not what this is addressed to, and a
        // profile whose owner has published nothing still adds.
        //
        // The page answers at once: the slot empties and the line reads
        // Requested, rather than waiting for the friendship to come back
        // down the stream.
        setState(() => _pending = FriendStatus.requested);
        _run((acts) => acts.addFriend(widget.uid, handle: them.handle));
      case FriendStatus.incoming:
        final f = friendshipWith(
          myUid: myUid,
          theirUid: widget.uid,
          friendships: friendships,
        );
        if (f == null) return;
        setState(() => _pending = FriendStatus.accepted);
        _run((acts) => acts.acceptRequest(f.id));
      case FriendStatus.blockedByMe:
        _run((acts) => acts.unblock(widget.uid));
      case FriendStatus.requested:
      case FriendStatus.accepted:
        break;
    }
  }

  Future<void> _remove(
    PublicProfile them,
    List<Friendship> friendships,
    String myUid,
  ) async {
    final f = friendshipWith(
      myUid: myUid,
      theirUid: widget.uid,
      friendships: friendships,
    );
    if (f == null) return;
    final yes = await showSondrConfirm(
      context,
      title: removeFriendTitle(them.handle),
      body: removeFriendBody(them.handle),
      confirmLabel: 'Remove',
    );
    if (!yes || !mounted) return;
    await _run((acts) => acts.removeFriend(f.id));
  }

  /// The bar's right slot: reporting and blocking are both "this person
  /// is a problem", and asking which keeps the bar at three slots.
  ///
  /// The sheet is the confirms' own card, in the middle of the screen —
  /// never under the slot that opened it, so a second tap cannot pick
  /// anything.
  Future<void> _blockOrReport(PublicProfile them, String myUid) async {
    // No title. The slot was tapped on THEIR page, with their handle in
    // the hero above it — repeating it on the card said nothing and made
    // the two answers read as a subheading of their name.
    final choice = await showSondrChoice<String>(
      context,
      choices: const [
        (label: 'Report', value: 'report'),
        (label: 'Block', value: 'block'),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'block') {
      await _block(them, myUid);
      return;
    }
    final outcome = await reportThing(
      context,
      ref,
      type: ReportTarget.user,
      targetKey: widget.uid,
      targetOwnerUid: widget.uid,
      title: reportTitle(ReportTarget.user, handle: them.handle),
    );
    if (!mounted) return;
    switch (outcome) {
      case ReportOutcome.cancelled:
        break;
      case ReportOutcome.sent:
        // Reporting a person hides nothing — blocking is the thing that
        // does that, and it is a different decision.
        _thanks();
      case ReportOutcome.failed:
        _say(kReportFailed);
    }
  }

  /// The thank-you, in the status line, for a moment.
  void _thanks() {
    if (!mounted) return;
    final token = ++_noticeToken;
    setState(() {
      _notice = kReportThanks;
      _noticeIsQuiet = true;
    });
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted && _noticeToken == token) setState(() => _notice = null);
    });
  }

  /// Which notice is current, so an older one cannot clear a newer.
  int _noticeToken = 0;

  Future<void> _block(PublicProfile them, String myUid) async {
    final yes = await showSondrConfirm(
      context,
      title: blockTitle(them.handle),
      body: blockBody(them.handle),
      confirmLabel: 'Block',
    );
    if (!yes || !mounted) return;
    await _run((acts) => acts.block(
          uid: widget.uid,
          handle: them.handle,
          displayName: them.displayName,
        ));
  }
}

/// The two confirms, named where there is a name to use.
///
/// Both actions sit in the bar, under the thumb that reaches for a tab, so
/// neither acts on a tap: they ask first, in a card in the middle of the
/// screen, nowhere near the slot that opened it. A second tap on the bar
/// lands on the card's scrim.
String removeFriendTitle(String handle) =>
    'Remove ${handle.isEmpty ? 'them' : handle}?';

String removeFriendBody(String handle) =>
    'You\'ll stop seeing each other\'s posts.';

String blockTitle(String handle) =>
    'Block ${handle.isEmpty ? 'them' : handle}?';

String blockBody(String handle) =>
    'They won\'t be able to see your profile or posts.';

/// Who to say this is.
///
/// Their published profile if there is one; otherwise whatever the entry
/// point already held — a post's byline, a search result, a friendship's
/// denormalised identity. Every one of those knew a handle, which is why
/// "Someone" should only ever appear for a page nobody could name.
///
/// The hours are the published copy's alone: a handle from a byline says
/// nothing about how long they have worked, and 0 would be a claim.
PublicProfile profileIdentity({
  required String uid,
  required PublicProfile? published,
  required String handle,
  required String displayName,
  required FriendIdentity? fromFriendship,
}) {
  String first(List<String> candidates) => candidates.firstWhere(
        (c) => c.isNotEmpty,
        orElse: () => '',
      );
  return PublicProfile(
    uid: uid,
    handle: first([
      published?.handle ?? '',
      handle,
      fromFriendship?.username ?? '',
    ]),
    displayName: first([
      published?.displayName ?? '',
      displayName,
      fromFriendship?.displayName ?? '',
    ]),
    hours: published?.hours ?? 0,
    seconds: published?.seconds,
    ringProgress: published?.ringProgress ?? 0,
  );
}

/// The newest shared milestone photo, or null when they have shared none.
String? _ringPhoto(List<MilestonePost> milestones) {
  for (final p in milestones) {
    if (p.photos.isNotEmpty) return p.photos.first.url;
  }
  return null;
}

/// The handle, and under it the one thing this page is for: where you
/// stand with them.
///
/// The status sits in the subtitle's slot — the line the personal Profile
/// uses for "Nh to your next milestone" — at the same size, because it
/// answers the same question in the same place: what is going on with this
/// person. Add friend, Accept and Unblock are offers and take the page's
/// full tone; Requested and Friends are states, and a state that looks
/// tappable is a lie.
class _HeroCaption extends StatelessWidget {
  const _HeroCaption({
    required this.them,
    required this.status,
    required this.busy,
    required this.onAct,
  });

  final PublicProfile them;
  final FriendStatus status;
  final bool busy;
  final VoidCallback onAct;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final actionable = friendStatusIsActionable(status) && !busy;
    final label = friendStatusLabel(status);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13 * scale,
      // The WEIGHT is the same either way, so a statement does not change
      // size and shift what sits under it. Tone carries it.
      fontWeight: FontWeight.w700,
      color: actionable ? tokens.textPrimary : tokens.textTertiary,
    );

    // A page with nothing to report keeps the line's HEIGHT: the stats,
    // the sections and the grid below them do not move as the state
    // changes under them. An empty Text rather than a measured box, so
    // the space is the line's own and cannot drift from it.
    final Widget line = Text(label, textAlign: TextAlign.center, style: style);

    return Column(
      children: [
        Text(
          // No "@". The handle is their name here, the same reading the
          // friends list and my own page take.
          them.handle.isEmpty ? 'Someone' : them.handle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 20 * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        SizedBox(height: kProfileHandleToSubline * scale),
        if (!actionable)
          line
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAct,
            child: line,
          ),
      ],
    );
  }
}

/// The hero: their newest shared milestone photo, or their initial, inside a
/// ring filled toward their next 20-hour mark.
///
/// The fill is computed from the hours they publish — `hours % 20` of the
/// way through the current band — which costs nothing beyond the figure
/// already on the page. A stranger's ring is the bare track: with no photo
/// and nothing shared, a filled ring would be claiming knowledge the page
/// does not have.
class _Emblem extends StatelessWidget {
  const _Emblem({
    required this.them,
    required this.photoUrl,
    required this.fill,
  });

  final PublicProfile them;
  final String? photoUrl;

  /// Whether the ring shows how far through their band they are — a
  /// friend's page does, a stranger's does not.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    return Center(
      child: ProgressRing(
        size: kProfileEmblemSize * scale,
        stroke: ringStroke(scale),
        // A friend's ring fills the way their own does. A stranger's is
        // the bare track: what they are working on is not a stranger's
        // business, and a ring filled to nothing would be a claim.
        progress: shownProgress(fill ? them.ringProgress : 0),
        center: SizedBox(
          width: kProfileEmblemPhoto * scale,
          height: kProfileEmblemPhoto * scale,
          child: photoUrl == null
              ? Center(
                  child: Text(
                    them.initial,
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontSize: 44 * scale,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                )
              : ClipOval(
                  child: SondrPhoto(
                    url: photoUrl!,
                    saturation: kProfilePhotoSaturation,
                    tint: kProfilePhotoTint,
                    placeholder: (_) => ColoredBox(color: tokens.surface),
                    error: (_) => ColoredBox(color: tokens.surface),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Their figures: hours always, and — for a friend — how many milestones
/// they have shared. Equal shares of the width, as on my own page.
class _Stats extends StatelessWidget {
  const _Stats({required this.hours, required this.milestones});

  /// Null when they have published nothing — unknown, which is not zero.
  final int? hours;

  /// Null for a stranger, who sees hours alone.
  final int? milestones;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (hours != null)
        Expanded(
          child: ProfileStat(
            value: '$hours',
            label: hours == 1 ? 'hour' : 'hours',
          ),
        ),
      if (milestones != null)
        Expanded(
          child: ProfileStat(
            value: '$milestones',
            label: milestones == 1 ? 'milestone' : 'milestones',
          ),
        ),
    ],
  );
}

/// A section break: the hairline, with more air above it than below, so the
/// heading hugs what it introduces.
class _Break extends StatelessWidget {
  const _Break({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: kProfileBreak * scale),
        // Inside the gutter, like every rule on the personal Profile: a
        // line that runs to the screen's edge reads as a divider between
        // two pages rather than a break between two sections.
        const ProfileGutter(child: ProfileHairline()),
        SizedBox(height: kProfileUnderHairline * scale),
        child,
      ],
    );
  }
}

/// A heading, its count, and a strip of what it counts.
///
/// The count is every post of that kind the reader is allowed to see; the
/// strip is the ones with a photo, the same rule my own Milestones strip
/// takes — a post with nothing to show is counted and not pictured. The
/// heading opens the lot as a grid.
/// The Posts heading, and the first row of its grid.
///
/// The heading opens the lot as a page; a tile opens one post. The count
/// is every post the reader may see — a post with no photo is counted and
/// not pictured, the same rule the strip above it takes.
class _PostsHead extends StatelessWidget {
  const _PostsHead({
    required this.uid,
    required this.handle,
    required this.count,
    required this.firstRow,
    required this.tile,
  });

  final String uid;
  final String handle;
  final int count;
  final List<Post> firstRow;
  final double tile;

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileGutter(
          child: ProfileHeading(
            label: 'Posts',
            // The last section's heading stands in the box "In progress"
            // stands in — see ProfileHeading.tight.
            tight: true,
            count: count == 0 ? null : profileCountLabel(count),
            onTap: count == 0
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PostsGridScreen(
                          uid: uid,
                          handle: handle,
                          title: 'Posts',
                          milestonesOnly: false,
                        ),
                      ),
                    ),
          ),
        ),
        if (firstRow.isNotEmpty) ...[
          SizedBox(height: kProfileHeadingToRings * scale),
          ProfileGutter(child: _GridRow(photos: firstRow, tile: tile)),
        ],
      ],
    );
  }
}

/// One row of the Posts grid: up to four tiles, the gap between them, and
/// nothing stretched to fill a short last row.
class _GridRow extends StatelessWidget {
  const _GridRow({required this.photos, required this.tile});

  final List<Post> photos;
  final double tile;

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < photos.length; i++) ...[
          if (i > 0) SizedBox(width: kProfileStripGap * scale),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showSinglePost(context, photos[i]),
            child: ProfileStripTile(
              url: photos[i].photos.first.url,
              side: tile,
            ),
          ),
        ],
      ],
    );
  }
}

class _PostSection extends ConsumerWidget {
  const _PostSection({
    required this.label,
    required this.uid,
    required this.handle,
    required this.posts,
    required this.milestonesOnly,
  });

  final String label;
  final String uid;
  final String handle;
  final List<Post> posts;
  final bool milestonesOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = figmaScale(context);
    final pictured = [
      for (final p in posts)
        if (p.photos.isNotEmpty) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileGutter(
          child: ProfileHeading(
            label: label,
            count: posts.isEmpty ? null : profileCountLabel(posts.length),
            onTap: posts.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PostsGridScreen(
                          uid: uid,
                          handle: handle,
                          title: label,
                          milestonesOnly: milestonesOnly,
                        ),
                      ),
                    ),
          ),
        ),
        if (pictured.isNotEmpty) ...[
          SizedBox(height: kProfileHeadingToPhotos * scale),
          // Full-bleed: the viewport is the screen and the margin is the
          // scroller's own padding, so the first tile starts on the margin
          // and the last can be dragged to it.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: kProfileGutter * scale),
            child: Row(
              children: [
                for (var i = 0; i < pictured.length; i++) ...[
                  if (i > 0) SizedBox(width: kProfileStripGap * scale),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showSinglePost(context, pictured[i]),
                    child: ProfileStripTile(
                      url: pictured[i].photos.first.url,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Their posts as a grid, laid out like the Photos lens: three across,
/// squares, newest first. A post with no photo is not here — the grid is
/// photos — and the heading's count said how many there are either way.
class PostsGridScreen extends ConsumerWidget {
  const PostsGridScreen({
    super.key,
    required this.uid,
    required this.handle,
    required this.title,
    required this.milestonesOnly,
  });

  final String uid;
  final String handle;
  final String title;
  final bool milestonesOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final async = ref.watch(profilePostsProvider(uid));
    if (!async.hasValue) return Scaffold(backgroundColor: tokens.background);
    final posts = [
      for (final p in async.value ?? const <Post>[])
        if ((!milestonesOnly || p is MilestonePost) && p.photos.isNotEmpty) p,
    ];
    final gap = kSpacingPair * scale;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: kProfileGutter * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: kSpacingSection * scale),
              // You arrived by tapping the heading this grid is OF, so
              // naming it again says nothing. The height stays, so the
              // first row of photos does not move.
              SizedBox(
                height: lineHeightOf(
                  context,
                  theme.textTheme.titleLarge,
                  kProfileHeadingSize,
                ),
              ),
              SizedBox(height: kSpacingSection * scale),
              if (posts.isEmpty)
                Text(
                  'Nothing with a photo yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13 * scale,
                    color: tokens.textSecondary,
                  ),
                )
              else
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  crossAxisCount: 3,
                  mainAxisSpacing: gap,
                  crossAxisSpacing: gap,
                  children: [
                    for (final p in posts)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showSinglePost(context, p),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10 * scale),
                          child: SondrPhoto(
                            url: p.photos.first.url,
                            saturation: kProfilePhotoSaturation,
                            tint: kProfilePhotoTint,
                            placeholder: (_) =>
                                ColoredBox(color: tokens.ringTrack),
                            error: (_) => ColoredBox(color: tokens.ringTrack),
                          ),
                        ),
                      ),
                  ],
                ),
              SizedBox(height: kSpacingSection * scale),
              Center(
                child: SondrAction(
                  label: 'Back',
                  supporting: true,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              SizedBox(height: kSpacingSection * scale),
            ],
          ),
        ),
      ),
    );
  }
}

/// Their friends: one row each, every row a way into that person's profile.
/// My own row goes to my Profile tab rather than opening a second copy of
/// it.
///
/// Readable because we are friends — the mirror's rule says so. A refusal
/// comes back as an empty list, which is the same thing a profile with no
/// friends shows, and that is the point: not being allowed is not an error.
class FriendsOfScreen extends ConsumerWidget {
  const FriendsOfScreen({super.key, required this.uid, required this.handle});

  final String uid;
  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final async = ref.watch(friendUidsProvider(uid));
    if (!async.hasValue) return Scaffold(backgroundColor: tokens.background);
    final uids = async.value ?? const <String>[];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: kSpacingSection * scale),
            // Where the title used to be. You arrived by tapping "Friends"
            // on their profile, so the page naming itself again told you
            // nothing — but the rows were composed against this much air
            // above them, so the air stays.
            SizedBox(
              height: lineHeightOf(
                context,
                theme.textTheme.titleLarge,
                kProfileHeadingSize,
              ),
            ),
            SizedBox(height: kSpacingSection * scale),
            Expanded(
              child: uids.isEmpty
                  ? ProfileGutter(
                      child: Text(
                        'No friends to show.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13 * scale,
                          color: tokens.textSecondary,
                        ),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final friendUid in uids)
                          _FriendOfRow(uid: friendUid),
                      ],
                    ),
            ),
            Center(
              child: SondrAction(
                label: 'Back',
                supporting: true,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            SizedBox(height: kSpacingSection * scale),
          ],
        ),
      ),
    );
  }
}

/// One person in their friends list. The name comes from that person's own
/// published profile — the mirror holds nothing but the uid, so a name here
/// can neither go stale nor be forged.
class _FriendOfRow extends ConsumerWidget {
  const _FriendOfRow({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final them = ref.watch(publicProfileProvider(uid)).value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openProfile(
        context,
        ref,
        uid,
        handle: them?.handle ?? '',
        displayName: them?.displayName ?? '',
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: kProfileGutter * scale,
          vertical: 10 * scale,
        ),
        child: Row(
          children: [
            Container(
              width: 36 * scale,
              height: 36 * scale,
              decoration: BoxDecoration(
                color: tokens.surface,
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: kSpacingBase * scale),
            Expanded(
              child: Text(
                them?.handle.isNotEmpty == true ? them!.handle : 'Someone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
