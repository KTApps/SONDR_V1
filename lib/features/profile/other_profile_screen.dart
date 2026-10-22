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
import '../../shared/sondr_prompt.dart';
import '../auth/guest_prompts.dart';
import '../feed/models/post.dart';
import '../feed/posts_repository.dart';
import '../feed/single_post_screen.dart';
import '../friends/friends_repository.dart';
import '../friends/models/friendship.dart';
import '../shell/main_shell.dart';
import '../tasks/models/task.dart';
import 'friend_status.dart';
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
  const OtherProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<OtherProfileScreen> createState() => _OtherProfileScreenState();
}

/// Their profile, pushed. My own page is a tab, not a push — so a row for
/// me (in their friends list, or a byline on my own post) switches to it
/// rather than opening a second copy of it.
void openProfile(BuildContext context, WidgetRef ref, String uid) {
  if (uid.isEmpty) return;
  if (uid == ref.read(currentUidProvider)) {
    ref.read(selectedTabProvider.notifier).set(kProfileTabIndex);
    Navigator.of(context).popUntil((route) => route.isFirst);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => OtherProfileScreen(uid: uid)),
  );
}

/// Home · Feed · Profile.
const int kProfileTabIndex = 2;

class _OtherProfileScreenState extends ConsumerState<OtherProfileScreen> {
  String? _notice;
  bool _busy = false;

  void _say(String message) {
    if (mounted) setState(() => _notice = message);
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
      // handle that does not exist.
      _say(e.message);
    } catch (e) {
      debugPrint('SONDR profile action error: ${e.runtimeType}');
      _say('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final myUid = ref.watch(currentUidProvider) ?? '';
    final friendships = ref.watch(friendshipsProvider).value ?? const <Friendship>[];
    final status = friendStatusOf(
      myUid: myUid,
      theirUid: widget.uid,
      friendships: friendships,
      blockedUids: ref.watch(blockedUidsProvider),
    );
    final sees = friendStatusSeesContent(status);

    final publicAsync = ref.watch(publicProfileProvider(widget.uid));
    final postsAsync = ref.watch(profilePostsProvider(widget.uid));
    final friendsAsync = ref.watch(friendUidsProvider(widget.uid));

    // One gate for the page: nothing is painted until everything it would
    // paint is known, so no section arrives a frame after the rest.
    final ready = publicAsync.hasValue &&
        (!sees || (postsAsync.hasValue && friendsAsync.hasValue));
    if (!ready) return Scaffold(backgroundColor: tokens.background);

    // Someone on an older build has published nothing. Their handle is
    // still denormalised onto our friendship, so the page is not blank.
    final them = publicAsync.value ??
        _fromFriendship(widget.uid, myUid, friendships);
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

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: kProfileTopMargin * scale),
              _Emblem(them: them, photoUrl: sees ? _ringPhoto(milestones) : null),
              SizedBox(height: kProfileHeroGap * scale),
              Center(
                child: Text(
                  // No "@": the handle is their name here, the same reading
                  // the friends list and my own page take.
                  them.handle.isEmpty ? 'Someone' : them.handle,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 20 * scale,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: kSpacingSection * scale),
              ProfileGutter(
                child: _Stats(
                  hours: them.hours,
                  milestones: sees ? milestones.length : null,
                ),
              ),
              SizedBox(height: kSpacingSection * scale),
              Center(
                child: SondrAction(
                  label: friendStatusLabel(status),
                  supporting: false,
                  onPressed: _busy || !friendStatusIsActionable(status)
                      ? null
                      : () => _act(status, them, friendships, myUid),
                ),
              ),
              if (!sees) ...[
                SizedBox(height: kSpacingBase * scale),
                ProfileGutter(
                  child: Text(
                    'Add each other as friends to see posts and milestones.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13 * scale,
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ],
              if (_notice != null) ...[
                SizedBox(height: kSpacingBase * scale),
                ProfileGutter(
                  child: SondrError(_notice!, textAlign: TextAlign.center),
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
                _Break(
                  child: _PostSection(
                    label: 'Posts',
                    uid: widget.uid,
                    handle: them.handle,
                    posts: posts,
                    milestonesOnly: false,
                  ),
                ),
              ],
              // A scroll away, like Sign out: the two things you would be
              // sorry to tap by accident.
              SizedBox(height: kProfileBreak * scale),
              const ProfileHairline(),
              SizedBox(height: kProfileUnderHairline * scale),
              if (status == FriendStatus.accepted)
                Center(
                  child: SondrAction(
                    label: 'Remove friend',
                    supporting: true,
                    onPressed: _busy
                        ? null
                        : () => _remove(them, friendships, myUid),
                  ),
                ),
              if (status != FriendStatus.blockedByMe)
                Center(
                  child: SondrAction(
                    label: 'Block',
                    supporting: true,
                    onPressed: _busy ? null : () => _block(them, myUid),
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
        _run((acts) => acts.addFriend(widget.uid, handle: them.handle));
      case FriendStatus.incoming:
        final f = friendshipWith(
          myUid: myUid,
          theirUid: widget.uid,
          friendships: friendships,
        );
        if (f != null) _run((acts) => acts.acceptRequest(f.id));
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
      title: 'Remove friend?',
      body: removeFriendBody(them.handle),
      confirmLabel: 'Remove',
    );
    if (!yes || !mounted) return;
    await _run((acts) => acts.removeFriend(f.id));
  }

  Future<void> _block(PublicProfile them, String myUid) async {
    final yes = await showSondrConfirm(
      context,
      title: 'Block this person?',
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

/// What removing a friend costs, said plainly. Named where there is a name
/// to use, because the page can be reached from a list and the person you
/// mean should not be in doubt.
String removeFriendBody(String handle) =>
    '${handle.isEmpty ? 'They' : handle} will stop seeing your posts, and '
    'you theirs. You can add each other again later.';

/// What blocking does. The second clause is the prune: blocking takes the
/// other person out of the audiences of everything this user has already
/// written, which is why it is not simply an unfriend.
String blockBody(String handle) =>
    '${handle.isEmpty ? 'They' : handle} will not see your posts or be able '
    'to add you, and they are taken out of the posts and comments you have '
    'already written.';

/// Their published profile is missing, so take what our friendship knows.
PublicProfile _fromFriendship(
  String uid,
  String myUid,
  List<Friendship> friendships,
) {
  final f = friendshipWith(myUid: myUid, theirUid: uid, friendships: friendships);
  final identity = f?.profiles[uid];
  return PublicProfile(
    uid: uid,
    handle: identity?.username ?? '',
    displayName: identity?.displayName ?? '',
    hours: 0,
  );
}

/// The newest shared milestone photo, or null when they have shared none.
String? _ringPhoto(List<MilestonePost> milestones) {
  for (final p in milestones) {
    if (p.photos.isNotEmpty) return p.photos.first.url;
  }
  return null;
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
  const _Emblem({required this.them, required this.photoUrl});

  final PublicProfile them;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final intoBand = them.hours % Task.milestoneStepHours;
    return Center(
      child: ProgressRing(
        size: kProfileEmblemSize * scale,
        stroke: ringStroke(scale),
        progress: photoUrl == null
            ? shownProgress(0)
            : shownProgress(intoBand / Task.milestoneStepHours),
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

  final int hours;

  /// Null for a stranger, who sees hours alone.
  final int? milestones;

  @override
  Widget build(BuildContext context) => Row(
    children: [
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
        const ProfileHairline(),
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
              Text(
                handle.isEmpty ? title : '$handle’s ${title.toLowerCase()}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: kProfileHeadingSize * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
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
            ProfileGutter(
              child: Text(
                handle.isEmpty
                    ? 'Friends'
                    : '$handle’s friends',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: kProfileHeadingSize * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
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
      onTap: () => openProfile(context, ref, uid),
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
