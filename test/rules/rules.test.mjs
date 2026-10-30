import { strict as assert } from 'node:assert';
import { after, before, beforeEach, describe, it } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  arrayRemove, collection, collectionGroup, deleteDoc, doc, getDoc, getDocs,
  increment, limit, orderBy, query, serverTimestamp, setDoc, updateDoc, where,
  writeBatch,
} from 'firebase/firestore';

/**
 * The one thing the Dart suite cannot see.
 *
 * Rules are not filters. A query succeeds only if the rules can prove every
 * matching document is readable without evaluating them one at a time — so a
 * read rule that depends on per-document data the query does not constrain
 * makes the WHOLE query fail with permission-denied, rather than returning
 * the rows that are allowed. A reader who has been pruned out of one comment
 * must get a shorter thread, never an error.
 */

const A = 'uid_author';
const B = 'uid_blocked';
const C = 'uid_friend';
/// A fourth party, friends with nobody — the stranger's view of a profile.
const D = 'uid_stranger';

/// The friendships document id for a pair. Byte-identical to
/// Friendship.pairId in lib/features/friends/models/friendship.dart AND to
/// pairId() in firestore.rules; the test below proves all three agree by
/// writing with one and reading under the other.
function pairId(a, b) { return [a, b].sort().join('__'); }

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-sondr',
    firestore: {
      rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: readFileSync(new URL('../../storage.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

after(async () => { await env?.cleanup(); });

/** Seed as admin, bypassing rules. */
async function seed(fn) {
  await env.withSecurityRulesDisabled(async (ctx) => { await fn(ctx.firestore()); });
}

function as(uid) { return env.authenticatedContext(uid).firestore(); }

describe('posts', () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/p1'), {
        authorUid: A, audience: [A, B, C], createdAt: 1, caption: 'x',
      });
      await setDoc(doc(db, 'posts/p2'), {
        authorUid: A, audience: [A, C], createdAt: 2, caption: 'y',
      });
    });
  });

  it('a post carrying the story fields is accepted — nothing validates keys', async () => {
    const db = as(A);
    await assertSucceeds(setDoc(doc(db, 'posts/story1'), {
      authorUid: A, audience: [A, B], type: 'milestone', createdAt: serverTimestamp(),
      taskName: 'Spanish', milestoneHours: 20, totalHours: 21,
      photos: [{ url: 'u', storagePath: 'p', sessionIndex: 0 }],
      sessions: [{ at: 1000, seconds: 3600, photo: true }],
      unit: 'session',
    }));
    // Leave the fixtures as the other tests expect them.
    await assertSucceeds(deleteDoc(doc(db, 'posts/story1')));
  });

  it('the feed query returns what the reader is in', async () => {
    const q = query(collection(as(C), 'posts'),
      where('audience', 'array-contains', C), orderBy('createdAt', 'desc'));
    const snap = await assertSucceeds(getDocs(q));
    assert.equal(snap.size, 2);
  });

  it('a pruned reader gets a SHORTER feed, not an error', async () => {
    const q = query(collection(as(B), 'posts'),
      where('audience', 'array-contains', B), orderBy('createdAt', 'desc'));
    const snap = await assertSucceeds(getDocs(q));
    assert.equal(snap.size, 1, 'B should see only the post they are still in');
  });

  it('an unfiltered feed query is denied outright', async () => {
    await assertFails(getDocs(collection(as(B), 'posts')));
  });

  it('a pending post reaches nobody but its author until the author widens it', async () => {
    await assertSucceeds(setDoc(doc(as(A), 'posts/pending1'), {
      authorUid: A, audience: [A], pending: true, type: 'milestone', createdAt: 5,
      taskName: 'Spanish', milestoneHours: 20, totalHours: 20, photos: [{ url: 'file:///x.jpg', storagePath: '' }],
    }));
    await assertSucceeds(getDoc(doc(as(A), 'posts/pending1')));
    await assertFails(getDoc(doc(as(B), 'posts/pending1')));
    // The one update that finishes it: the author widens the audience.
    await assertSucceeds(updateDoc(doc(as(A), 'posts/pending1'), {
      audience: [A, B], pending: false, photos: [{ url: 'https://x/0.jpg', storagePath: 'users/A/posts/pending1/0.jpg' }],
    }));
    await assertSucceeds(getDoc(doc(as(B), 'posts/pending1')));
    await assertSucceeds(deleteDoc(doc(as(A), 'posts/pending1')));
  });

  it('the author may prune the audience', async () => {
    await assertSucceeds(
      updateDoc(doc(as(A), 'posts/p1'), { audience: [A, C] }));
  });

  it('a reader may not rewrite someone else\'s audience', async () => {
    await assertFails(
      updateDoc(doc(as(C), 'posts/p2'), { audience: [A, C, B] }));
  });
});

describe('comments', () => {
  beforeEachSeed();

  function beforeEachSeed() {
    before(async () => {
      await env.clearFirestore();
      await seed(async (db) => {
        await setDoc(doc(db, 'posts/p1'), {
          authorUid: C, audience: [A, B, C], createdAt: 1,
        });
        // A's comment, still visible to everyone in the post audience.
        await setDoc(doc(db, 'posts/p1/comments/c1'), {
          authorUid: A, audience: [A, B, C], text: 't', createdAt: 1,
        });
        // A's comment, pruned so B is no longer in it.
        await setDoc(doc(db, 'posts/p1/comments/c2'), {
          authorUid: A, audience: [A, C], text: 't', createdAt: 2,
        });
      });
    });
  }

  it('a reader in every audience sees the whole thread', async () => {
    const q = query(collection(as(C), 'posts/p1/comments'),
      where('audience', 'array-contains', C), orderBy('createdAt'));
    const snap = await assertSucceeds(getDocs(q));
    assert.equal(snap.size, 2);
  });

  it('a pruned reader gets a SHORTER thread, not an error', async () => {
    const q = query(collection(as(B), 'posts/p1/comments'),
      where('audience', 'array-contains', B), orderBy('createdAt'));
    const snap = await assertSucceeds(getDocs(q));
    assert.equal(snap.size, 1, 'B should see only the comment they are still in');
  });

  it('a thread query without the audience filter is denied outright', async () => {
    await assertFails(
      getDocs(query(collection(as(B), 'posts/p1/comments'), orderBy('createdAt'))));
  });

  it('someone outside the POST audience sees nothing, even if named in a comment',
    async () => {
      await seed(async (db) => {
        await setDoc(doc(db, 'posts/p1/comments/c3'), {
          authorUid: A, audience: [A, 'uid_outsider'], text: 't', createdAt: 3,
        });
      });
      const q = query(collection(as('uid_outsider'), 'posts/p1/comments'),
        where('audience', 'array-contains', 'uid_outsider'), orderBy('createdAt'));
      await assertFails(getDocs(q));
    });

  it('a comment must be created with the post\'s audience, exactly', async () => {
    await assertSucceeds(setDoc(doc(as(B), 'posts/p1/comments/ok'), {
      authorUid: B, audience: [A, B, C], text: 't', createdAt: 9,
    }));
  });

  it('a forged audience is denied — wider', async () => {
    await assertFails(setDoc(doc(as(B), 'posts/p1/comments/bad1'), {
      authorUid: B, audience: [A, B, C, 'uid_stranger'], text: 't', createdAt: 9,
    }));
  });

  it('a forged audience is denied — narrower', async () => {
    await assertFails(setDoc(doc(as(B), 'posts/p1/comments/bad2'), {
      authorUid: B, audience: [B], text: 't', createdAt: 9,
    }));
  });

  it('the author may narrow their own comment\'s audience', async () => {
    await assertSucceeds(
      updateDoc(doc(as(A), 'posts/p1/comments/c1'), { audience: [A, C] }));
  });

  it('widening an audience to an arbitrary list is denied', async () => {
    await assertFails(
      updateDoc(doc(as(A), 'posts/p1/comments/c2'), { audience: [A, B, C, D] }));
  });

  it('the author may widen their comment to exactly the post\'s audience', async () => {
    // c2 was pruned to [A, C]; the post reaches [A, B, C]. Following the
    // post is allowed — this is how a comment lets a new friend in.
    await assertSucceeds(
      updateDoc(doc(as(A), 'posts/p1/comments/c2'), { audience: [A, B, C] }));
  });

  it('a non-author may not widen it, even to the post\'s audience', async () => {
    await assertFails(
      updateDoc(doc(as(C), 'posts/p1/comments/c2'), { audience: [A, B, C] }));
  });

  it('changing the text alongside the audience is denied', async () => {
    await assertFails(updateDoc(doc(as(A), 'posts/p1/comments/c1'),
      { audience: [A], text: 'rewritten' }));
  });

  it('someone else may not prune your comment', async () => {
    await assertFails(
      updateDoc(doc(as(C), 'posts/p1/comments/c1'), { audience: [A] }));
  });
});

describe('who liked a post', () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/p1'), {
        authorUid: A, audience: [A, B, C], createdAt: 1,
      });
    });
  });

  it('a liker can create and delete their own like', async () => {
    await assertSucceeds(setDoc(doc(as(C), 'posts/p1/likes/' + C), { at: 1 }));
    await assertSucceeds(deleteDoc(doc(as(C), 'posts/p1/likes/' + C)));
  });

  it('a liker cannot write a like in someone else\'s name', async () => {
    await assertFails(setDoc(doc(as(C), 'posts/p1/likes/' + B), { at: 1 }));
  });

  it('someone the post does not reach can neither like nor look', async () => {
    await assertFails(setDoc(doc(as(D), 'posts/p1/likes/' + D), { at: 1 }));
    await assertFails(getDocs(collection(as(D), 'posts/p1/likes')));
  });

  it('anyone the post reaches can list the likes — the author included', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/p1/likes/' + C), { at: 1 });
      await setDoc(doc(db, 'posts/p1/likes/' + B), { at: 2 });
    });
    const mine = await assertSucceeds(
      getDocs(query(collection(as(A), 'posts/p1/likes'), orderBy('at', 'desc'))));
    assert.deepEqual(mine.docs.map((d) => d.id), [B, C]);
    const theirs = await assertSucceeds(getDocs(collection(as(B), 'posts/p1/likes')));
    assert.equal(theirs.size, 2);
  });
});

describe('replies', () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/p1'), { authorUid: C, audience: [A, B, C], createdAt: 1 });
      await setDoc(doc(db, 'posts/p1/comments/top'), {
        authorUid: A, audience: [A, B, C], text: 't', createdAt: 1,
      });
      await setDoc(doc(db, 'posts/p1/comments/reply1'), {
        authorUid: B, audience: [A, B, C], text: 'r', createdAt: 2, parentId: 'top',
      });
    });
  });

  it('a reply names an existing top-level comment on the same post', async () => {
    await assertSucceeds(setDoc(doc(as(C), 'posts/p1/comments/r2'), {
      authorUid: C, audience: [A, B, C], text: 'ok', createdAt: 3, parentId: 'top',
    }));
  });

  it('a reply to a missing parent is refused', async () => {
    await assertFails(setDoc(doc(as(C), 'posts/p1/comments/r3'), {
      authorUid: C, audience: [A, B, C], text: 'x', createdAt: 3, parentId: 'nope',
    }));
  });

  it('a reply to a reply is refused — one level, never deeper', async () => {
    await assertFails(setDoc(doc(as(C), 'posts/p1/comments/r4'), {
      authorUid: C, audience: [A, B, C], text: 'x', createdAt: 3, parentId: 'reply1',
    }));
  });

  it("the parent's author may delete a reply under their comment", async () => {
    await assertSucceeds(deleteDoc(doc(as(A), 'posts/p1/comments/reply1')));
  });

  it('nobody else may delete somebody\'s reply', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/p1/comments/reply5'), {
        authorUid: B, audience: [A, B, C], text: 'r', createdAt: 2, parentId: 'top',
      });
    });
    // D is a stranger to the post. C, who IS its author, may clear it —
    // see "what a deletion may reach": a post's author takes down what is
    // under their own post.
    await assertFails(deleteDoc(doc(as(D), 'posts/p1/comments/reply5')));
  });
});

describe('notifications', () => {
  const base = (type, extra = {}) => ({
    type, actorUid: A, actorHandle: 'tom', at: serverTimestamp(), ...extra,
  });
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      // A and C are friends; A and D are strangers; B invited A.
      await setDoc(doc(db, 'friendships/' + pairId(A, C)), {
        users: [A, C].sort(), status: 'accepted', requestedBy: C,
      });
      await setDoc(doc(db, 'posts/p1'), { authorUid: C, audience: [A, C], createdAt: 1 });
      await setDoc(doc(db, 'usernames/bee'), { uid: B });
    });
  });

  it('a like goes to a friend, with exact keys', async () => {
    await assertSucceeds(setDoc(doc(as(A), 'notifications/' + C + '/items/n1'),
      base('like', { postId: 'p1' })));
  });

  it('a like with a stray key is refused', async () => {
    await assertFails(setDoc(doc(as(A), 'notifications/' + C + '/items/n2'),
      base('like', { postId: 'p1', extra: 1 })));
  });

  it('a like to a stranger is refused', async () => {
    await assertFails(setDoc(doc(as(A), 'notifications/' + D + '/items/n3'),
      base('like', { postId: 'p1' })));
  });

  it('nothing to yourself', async () => {
    await assertFails(setDoc(doc(as(A), 'notifications/' + A + '/items/n4'),
      base('like', { postId: 'p1' })));
  });

  it('the actor must be the signed-in user', async () => {
    await assertFails(setDoc(doc(as(C), 'notifications/' + A + '/items/n5'),
      base('like', { postId: 'p1' })));
  });

  it('the clock is the server\'s', async () => {
    await assertFails(setDoc(doc(as(A), 'notifications/' + C + '/items/n6'),
      { ...base('like', { postId: 'p1' }), at: 123 }));
  });

  it('a comment and a reply carry the comment id', async () => {
    await assertSucceeds(setDoc(doc(as(A), 'notifications/' + C + '/items/n7'),
      base('comment', { postId: 'p1', commentId: 'c1' })));
    await assertSucceeds(setDoc(doc(as(A), 'notifications/' + C + '/items/n8'),
      base('reply', { postId: 'p1', commentId: 'c1' })));
    await assertFails(setDoc(doc(as(A), 'notifications/' + C + '/items/n9'),
      base('comment', { postId: 'p1' })));
  });

  it('a milestone carries the task and the hours', async () => {
    await assertSucceeds(setDoc(doc(as(A), 'notifications/' + C + '/items/n10'),
      base('milestone', { postId: 'p1', taskName: 'Spanish', hours: 20 })));
    await assertFails(setDoc(doc(as(A), 'notifications/' + C + '/items/n11'),
      base('milestone', { postId: 'p1', taskName: 'Spanish' })));
  });

  it('a request notice lands with the request, in one batch — and not without it', async () => {
    const db = as(A);
    const b = writeBatch(db);
    b.set(doc(db, 'friendships/' + pairId(A, D)), {
      users: [A, D].sort(), status: 'pending', requestedBy: A,
      profiles: { [A]: { username: 'tom', displayName: 'Tom' } },
    });
    b.set(doc(db, 'notifications/' + D + '/items/req1'), base('request'));
    await assertSucceeds(b.commit());
    // A stranger with no request standing cannot say "wants to be friends".
    await assertFails(setDoc(doc(as(C), 'notifications/' + D + '/items/req2'),
      { type: 'request', actorUid: C, actorHandle: 'cass', at: serverTimestamp() }));
  });

  it('an acceptance lands with the accept', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'friendships/' + pairId(A, B)), {
        users: [A, B].sort(), status: 'pending', requestedBy: B,
        profiles: { [B]: { username: 'bee', displayName: 'Bee' } },
      });
    });
    const db = as(A);
    const b = writeBatch(db);
    b.update(doc(db, 'friendships/' + pairId(A, B)), {
      status: 'accepted', acceptedAt: serverTimestamp(),
      [`profiles.${A}`]: { username: 'tom', displayName: 'Tom' },
    });
    b.set(doc(db, 'publicProfiles/' + A + '/friends/' + B), { since: serverTimestamp() });
    b.set(doc(db, 'publicProfiles/' + B + '/friends/' + A), { since: serverTimestamp() });
    b.set(doc(db, 'notifications/' + B + '/items/acc1'), base('accepted'));
    await assertSucceeds(b.commit());
  });

  it('an invite notice lands with the invite record', async () => {
    const db = as(A);
    const b = writeBatch(db);
    b.set(doc(db, 'invites/' + A), { invitedBy: B, invitedByHandle: 'bee', at: serverTimestamp() });
    b.set(doc(db, 'notifications/' + B + '/items/inv1'), base('invite'));
    await assertSucceeds(b.commit());
    await assertFails(setDoc(doc(as(C), 'notifications/' + B + '/items/inv2'),
      { type: 'invite', actorUid: C, actorHandle: 'cass', at: serverTimestamp() }));
  });

  it('the recipient reads and deletes; an outsider does neither; nobody updates', async () => {
    const mine = await assertSucceeds(getDocs(query(
      collection(as(C), 'notifications/' + C + '/items'), orderBy('at', 'desc'), limit(100))));
    assert.ok(mine.size >= 1);
    // The inbox is never browsable by anyone but its owner, actor or not.
    await assertFails(getDocs(collection(as(A), 'notifications/' + C + '/items')));
    await assertFails(updateDoc(doc(as(C), 'notifications/' + C + '/items/n1'), { type: 'reply' }));
    await assertSucceeds(deleteDoc(doc(as(C), 'notifications/' + C + '/items/n1')));
    // B neither received n7 nor caused it (A did), so it is not theirs.
    await assertFails(deleteDoc(doc(as(B), 'notifications/' + C + '/items/n7')));
    // A, who caused it, may take it back — see "the notices an account
    // leaves in other people's inboxes".
    await assertSucceeds(deleteDoc(doc(as(A), 'notifications/' + C + '/items/n7')));
  });
});

describe('finding my own comments to prune', () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/p1'), { authorUid: C, audience: [A, B, C], createdAt: 1 });
      await setDoc(doc(db, 'posts/p2'), { authorUid: B, audience: [A, B], createdAt: 2 });
      await setDoc(doc(db, 'posts/p1/comments/c1'), {
        authorUid: A, audience: [A, B, C], text: 't', createdAt: 1 });
      await setDoc(doc(db, 'posts/p2/comments/c2'), {
        authorUid: A, audience: [A, B], text: 't', createdAt: 2 });
      await setDoc(doc(db, 'posts/p1/comments/c3'), {
        authorUid: C, audience: [A, B, C], text: 't', createdAt: 3 });
    });
  });

  it('the collection-group query returns my comments across posts', async () => {
    const { collectionGroup } = await import('firebase/firestore');
    const q = query(collectionGroup(as(A), 'comments'), where('authorUid', '==', A));
    const snap = await assertSucceeds(getDocs(q));
    assert.equal(snap.size, 2);
  });

  it('it cannot be used to read anyone else\'s', async () => {
    const { collectionGroup } = await import('firebase/firestore');
    const q = query(collectionGroup(as(A), 'comments'), where('authorUid', '==', C));
    await assertFails(getDocs(q));
  });

  it('an unfiltered collection-group query is denied', async () => {
    const { collectionGroup } = await import('firebase/firestore');
    await assertFails(getDocs(collectionGroup(as(A), 'comments')));
  });
});

/**
 * A profile for OTHER people.
 *
 * Nothing under users/{uid} is readable cross-user, so the facts a profile
 * shows are published into publicProfiles/{uid} by their owner, and their
 * friend list is mirrored into a subcollection whose PATH names the owner —
 * which is the only shape a friends-only list query can prove.
 */
describe('publicProfiles', () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'usernames/ada'), { uid: A });
      await setDoc(doc(db, 'usernames/cass'), { uid: C });
      await setDoc(doc(db, 'publicProfiles/' + A), {
        handle: 'ada', displayName: 'Ada', hours: 41, updatedAt: 1,
      });
    });
  });

  it('any signed-in user can read one', async () => {
    const snap = await assertSucceeds(getDoc(doc(as(D), 'publicProfiles/' + A)));
    assert.equal(snap.data().hours, 41);
  });

  it('a signed-out reader cannot', async () => {
    await assertFails(
      getDoc(doc(env.unauthenticatedContext().firestore(), 'publicProfiles/' + A)));
  });

  it('only the owner writes it', async () => {
    await assertSucceeds(setDoc(doc(as(A), 'publicProfiles/' + A), {
      handle: 'ada', displayName: 'Ada', hours: 42, updatedAt: 2,
    }));
    await assertFails(setDoc(doc(as(C), 'publicProfiles/' + A), {
      handle: 'ada', displayName: 'Not Ada', hours: 999, updatedAt: 3,
    }));
  });

  it('a handle the usernames index does not give them is refused', async () => {
    // Cass's own doc may not claim Ada's handle, and may not claim a handle
    // nobody has registered.
    await assertFails(setDoc(doc(as(C), 'publicProfiles/' + C), {
      handle: 'ada', displayName: 'Cass', hours: 1, updatedAt: 1,
    }));
    await assertFails(setDoc(doc(as(C), 'publicProfiles/' + C), {
      handle: 'nobody', displayName: 'Cass', hours: 1, updatedAt: 1,
    }));
    await assertSucceeds(setDoc(doc(as(C), 'publicProfiles/' + C), {
      handle: 'cass', displayName: 'Cass', hours: 1, updatedAt: 1,
    }));
  });
});

describe('the friend mirror', () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      // A and C are friends; A and D have a pending request; B is nobody's.
      await setDoc(doc(db, 'friendships/' + pairId(A, C)), {
        users: [A, C].sort(), requestedBy: A, status: 'accepted',
      });
      // A asked D, so D is the one who can accept it.
      await setDoc(doc(db, 'friendships/' + pairId(A, D)), {
        users: [A, D].sort(), requestedBy: A, status: 'pending',
      });
      await setDoc(doc(db, 'publicProfiles/' + A + '/friends/' + C), { since: 1 });
    });
  });

  it('a friend can list it', async () => {
    const snap = await assertSucceeds(
      getDocs(collection(as(C), 'publicProfiles/' + A + '/friends')));
    assert.deepEqual(snap.docs.map((d) => d.id), [C]);
  });

  it('the owner can always list their own', async () => {
    await assertSucceeds(
      getDocs(collection(as(A), 'publicProfiles/' + A + '/friends')));
  });

  it('a stranger is denied, and so is a pending relationship', async () => {
    await assertFails(
      getDocs(collection(as(B), 'publicProfiles/' + A + '/friends')));
    await assertFails(
      getDocs(collection(as(D), 'publicProfiles/' + A + '/friends')));
  });

  it('the pair id the rules build is the one Dart writes', async () => {
    // The friendship was seeded under the SORTED id. The read above found it
    // from C's side; this finds it from A's, so neither order can be the
    // only one that works.
    await assertSucceeds(
      getDocs(collection(as(A), 'publicProfiles/' + C + '/friends')));
  });

  it('an entry without an accepted friendship behind it is refused', async () => {
    // A's request to D is still pending.
    await assertFails(
      setDoc(doc(as(D), 'publicProfiles/' + D + '/friends/' + A), { since: 1 }));
    await assertFails(
      setDoc(doc(as(D), 'publicProfiles/' + A + '/friends/' + D), { since: 1 }));
    // And nobody can invent a friendship that was never asked for.
    await assertFails(
      setDoc(doc(as(B), 'publicProfiles/' + B + '/friends/' + A), { since: 1 }));
  });

  it('an entry carrying more than `since` is refused', async () => {
    await assertFails(
      setDoc(doc(as(C), 'publicProfiles/' + C + '/friends/' + A),
        { since: 1, handle: 'ada' }));
  });

  it('the accepter writes both halves in the same batch as the accept', async () => {
    const pair = pairId(A, D);
    const db = as(D);
    const batch = writeBatch(db);
    batch.update(doc(db, 'friendships/' + pair), { status: 'accepted' });
    batch.set(doc(db, 'publicProfiles/' + D + '/friends/' + A), { since: 2 });
    batch.set(doc(db, 'publicProfiles/' + A + '/friends/' + D), { since: 2 });
    await assertSucceeds(batch.commit());
  });

  it('either party can delete either half', async () => {
    // C removes themselves from A's list, and A removes C's copy.
    await assertSucceeds(
      deleteDoc(doc(as(C), 'publicProfiles/' + A + '/friends/' + C)));
    await seed(async (db) => {
      await setDoc(doc(db, 'publicProfiles/' + C + '/friends/' + A), { since: 1 });
    });
    await assertSucceeds(
      deleteDoc(doc(as(A), 'publicProfiles/' + C + '/friends/' + A)));
    // Someone outside the pair cannot.
    await seed(async (db) => {
      await setDoc(doc(db, 'publicProfiles/' + A + '/friends/' + C), { since: 1 });
    });
    await assertFails(
      deleteDoc(doc(as(B), 'publicProfiles/' + A + '/friends/' + C)));
  });
});

describe('the posts on a profile', () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      // Three of A's posts. C is in all three; B was pruned out of one;
      // D (a stranger) is in none.
      await setDoc(doc(db, 'posts/p1'), {
        authorUid: A, audience: [A, B, C], type: 'milestone', createdAt: 1 });
      await setDoc(doc(db, 'posts/p2'), {
        authorUid: A, audience: [A, C], type: 'session', createdAt: 2 });
      await setDoc(doc(db, 'posts/p3'), {
        authorUid: A, audience: [A, B, C], type: 'session', createdAt: 3 });
      // Someone else's post, to prove the author filter is doing something.
      await setDoc(doc(db, 'posts/p4'), {
        authorUid: C, audience: [A, B, C], type: 'session', createdAt: 4 });
    });
  });

  /** The query the profile screen runs. */
  function profilePosts(reader, author) {
    return query(
      collection(as(reader), 'posts'),
      where('authorUid', '==', author),
      where('audience', 'array-contains', reader),
      orderBy('createdAt', 'desc'),
      limit(100),
    );
  }

  it('returns the author\'s posts the reader is in', async () => {
    const snap = await assertSucceeds(getDocs(profilePosts(C, A)));
    assert.deepEqual(snap.docs.map((d) => d.id), ['p3', 'p2', 'p1']);
  });

  it('a pruned reader gets a SHORTER list, not an error', async () => {
    const snap = await assertSucceeds(getDocs(profilePosts(B, A)));
    assert.deepEqual(snap.docs.map((d) => d.id), ['p3', 'p1']);
  });

  it('a stranger gets an empty list, not an error', async () => {
    const snap = await assertSucceeds(getDocs(profilePosts(D, A)));
    assert.equal(snap.size, 0);
  });

  it('a non-author querying by authorUid alone is denied outright', async () => {
    // The audience clause has to be provable from the query. C is in every
    // one of these posts, and it still fails — the rule grants on audience
    // and the query does not constrain it, so the whole query goes rather
    // than the rows that are allowed.
    await assertFails(getDocs(query(
      collection(as(C), 'posts'),
      where('authorUid', '==', A),
      orderBy('createdAt', 'desc'),
    )));
  });
});

describe('a profile gives a block away nowhere', () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      // A has blocked B: the friendship is gone and B is pruned out of the
      // audiences. B must not be able to tell any of that apart from "we
      // were never friends".
      await setDoc(doc(db, 'usernames/ada'), { uid: A });
      await setDoc(doc(db, 'publicProfiles/' + A), {
        handle: 'ada', displayName: 'Ada', hours: 41, updatedAt: 1 });
      await setDoc(doc(db, 'blocks/' + A + '__' + B), { blocker: A, blocked: B });
      await setDoc(doc(db, 'posts/p1'), {
        authorUid: A, audience: [A], type: 'milestone', createdAt: 1 });
    });
  });

  it('the blocked reader still reads the public profile normally', async () => {
    const snap = await assertSucceeds(getDoc(doc(as(B), 'publicProfiles/' + A)));
    assert.equal(snap.data().handle, 'ada');
    // Byte for byte what a stranger sees.
    const theirs = await assertSucceeds(getDoc(doc(as(D), 'publicProfiles/' + A)));
    assert.deepEqual(snap.data(), theirs.data());
  });

  it('their posts query is empty, exactly as a stranger\'s is', async () => {
    const mine = await assertSucceeds(getDocs(query(
      collection(as(B), 'posts'),
      where('authorUid', '==', A),
      where('audience', 'array-contains', B),
      orderBy('createdAt', 'desc'),
    )));
    assert.equal(mine.size, 0);
  });

  it('the friend list is denied the same way it is for a stranger', async () => {
    await assertFails(
      getDocs(collection(as(B), 'publicProfiles/' + A + '/friends')));
    await assertFails(
      getDocs(collection(as(D), 'publicProfiles/' + A + '/friends')));
  });

  it('the block document itself stays invisible to the person blocked', async () => {
    await assertFails(getDoc(doc(as(B), 'blocks/' + A + '__' + B)));
  });
});

/**
 * Reports.
 *
 * A report is a message to us: the client writes one and can never read,
 * change or withdraw it. The id is derived from the reporter and the
 * target, so telling us twice about the same thing is refused by the
 * rules rather than counted twice — which the app treats as success,
 * because the person has already told us.
 */
describe('reports', () => {
  const ok = {
    reporterUid: A,
    targetType: 'post',
    targetKey: 'p1',
    targetOwnerUid: C,
    reason: 'spam',
  };
  // A comment's key carries a slash; the id cannot, so it swaps it.
  const id = (uid, type, key) =>
    `${uid}__${type}__${key.split('/').join('_')}`;

  before(async () => {
    await env.clearFirestore();
  });

  it('a signed-in user can report a post, a comment and a person', async () => {
    const db = as(A);
    await assertSucceeds(
      setDoc(doc(db, 'reports/' + id(A, 'post', 'p1')), {
        ...ok,
        createdAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      setDoc(doc(db, 'reports/' + id(A, 'comment', 'p1/c1')), {
        ...ok,
        targetType: 'comment',
        targetKey: 'p1/c1',
        reason: 'hate',
        createdAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      setDoc(doc(db, 'reports/' + id(A, 'user', C)), {
        ...ok,
        targetType: 'user',
        targetKey: C,
        reason: 'other',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('telling us the same thing twice is refused', async () => {
    // The app reads this as "already reported" and says thank you anyway.
    await assertFails(
      setDoc(doc(as(A), 'reports/' + id(A, 'post', 'p1')), {
        ...ok,
        reason: 'violence',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('a report cannot be filed in someone else\'s name', async () => {
    await assertFails(
      setDoc(doc(as(B), 'reports/' + id(A, 'post', 'p9')), {
        ...ok,
        targetKey: 'p9',
        createdAt: serverTimestamp(),
      }),
    );
    // Nor under an id that does not match what it says.
    await assertFails(
      setDoc(doc(as(B), 'reports/' + id(B, 'post', 'p9')), {
        ...ok,
        reporterUid: B,
        targetKey: 'somethingelse',
        createdAt: serverTimestamp(),
      }),
    );
    // And not at their OWN id while naming somebody else as the reporter,
    // which is the way round the id alone does not catch.
    await assertFails(
      setDoc(doc(as(B), 'reports/' + id(B, 'post', 'p9')), {
        ...ok,
        reporterUid: A,
        targetKey: 'p9',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('the type and the reason have to be ones we know', async () => {
    await assertFails(
      setDoc(doc(as(B), 'reports/' + id(B, 'photo', 'p1')), {
        ...ok,
        reporterUid: B,
        targetType: 'photo',
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(as(B), 'reports/' + id(B, 'post', 'p1')), {
        ...ok,
        reporterUid: B,
        reason: 'boring',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('nothing may be smuggled in alongside, and nothing left out', async () => {
    await assertFails(
      setDoc(doc(as(B), 'reports/' + id(B, 'post', 'p2')), {
        ...ok,
        reporterUid: B,
        targetKey: 'p2',
        createdAt: serverTimestamp(),
        note: 'an extra field',
      }),
    );
    await assertFails(
      setDoc(doc(as(B), 'reports/' + id(B, 'post', 'p3')), {
        reporterUid: B,
        targetType: 'post',
        targetKey: 'p3',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('the time is the server\'s, not the phone\'s', async () => {
    await assertFails(
      setDoc(doc(as(B), 'reports/' + id(B, 'post', 'p4')), {
        ...ok,
        reporterUid: B,
        targetKey: 'p4',
        createdAt: new Date(2000, 0, 1),
      }),
    );
  });

  it('nobody reads a report back — not even the person who sent it', async () => {
    await assertFails(getDoc(doc(as(A), 'reports/' + id(A, 'post', 'p1'))));
    await assertFails(getDocs(collection(as(A), 'reports')));
    await assertFails(
      updateDoc(doc(as(A), 'reports/' + id(A, 'post', 'p1')), {
        reason: 'other',
      }),
    );
    await assertFails(deleteDoc(doc(as(A), 'reports/' + id(A, 'post', 'p1'))));
  });
});

/**
 * What the reporter stops seeing.
 *
 * Hiding is the reporter's own business and lives under their own
 * document, which the owner-only rule already covers — this pins that it
 * really is only theirs.
 */
describe('hidden things', () => {
  before(async () => {
    await env.clearFirestore();
  });

  it('a person hides something for themselves', async () => {
    await assertSucceeds(
      setDoc(doc(as(A), `users/${A}/hidden/post__p1`), {
        hiddenAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(getDocs(collection(as(A), `users/${A}/hidden`)));
  });

  it('and nobody else can see or touch it', async () => {
    await assertFails(getDocs(collection(as(B), `users/${A}/hidden`)));
    await assertFails(
      setDoc(doc(as(B), `users/${A}/hidden/post__p2`), {
        hiddenAt: serverTimestamp(),
      }),
    );
  });
});

describe('giving up a handle', () => {
  /**
   * Deleting an account has to free its handle, and the client is the only
   * thing that can do it — there are no Cloud Functions here. So the
   * usernames index gained a delete rule, and this is the whole of what it
   * may allow: the owner, and nobody else.
   *
   * It stays immutable: an update would let a handle be pointed at another
   * uid in place, which is the theft the create rule exists to stop.
   */
  before(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'usernames/ada'), { uid: A });
    });
  });

  it('the owner can give up their own handle', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'usernames/owned'), { uid: A });
    });
    await assertSucceeds(deleteDoc(doc(as(A), 'usernames/owned')));
  });

  it('nobody else can take it away from them', async () => {
    await assertFails(deleteDoc(doc(as(B), 'usernames/ada')));
    await assertFails(deleteDoc(doc(as(C), 'usernames/ada')));
  });

  it('a signed-out client cannot either', async () => {
    const anon = env.unauthenticatedContext().firestore();
    await assertFails(deleteDoc(doc(anon, 'usernames/ada')));
  });

  it('and it is still immutable — no update, by anyone', async () => {
    await assertFails(updateDoc(doc(as(A), 'usernames/ada'), { uid: B }));
    await assertFails(updateDoc(doc(as(B), 'usernames/ada'), { uid: B }));
  });

  it('once given up, somebody else can claim it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'usernames/freed'), { uid: A });
    });
    // While A holds it, B cannot have it.
    await assertFails(setDoc(doc(as(B), 'usernames/freed'), { uid: B }));
    await assertSucceeds(deleteDoc(doc(as(A), 'usernames/freed')));
    await assertSucceeds(setDoc(doc(as(B), 'usernames/freed'), { uid: B }));
  });
});

describe('what a leaving account may delete', () => {
  /**
   * The cascade runs on the client as the departing user, so every delete
   * it makes has to be one the rules already allow. These are those
   * deletes, each as the leaving user — and each as somebody else, because
   * a rule that lets anyone delete another person's post would be a far
   * worse bug than a handle left behind.
   *
   * A is leaving. C is their friend and stays.
   */
  before(async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users/' + A + '/meta/profile'), { username: 'ada' });
      await setDoc(doc(db, 'users/' + A + '/tasks/t1'), { name: 'Golf' });
      await setDoc(doc(db, 'users/' + A + '/likes/p_c'), { at: 1 });
      await setDoc(doc(db, 'publicProfiles/' + A), {
        handle: 'ada', displayName: 'Ada', hours: 3,
        updatedAt: serverTimestamp(),
      });
      await setDoc(doc(db, 'publicProfiles/' + A + '/friends/' + C), { since: 1 });
      await setDoc(doc(db, 'publicProfiles/' + C + '/friends/' + A), { since: 1 });
      await setDoc(doc(db, 'friendships/' + pairId(A, C)), {
        users: [A, C], requestedBy: A, status: 'accepted',
      });
      await setDoc(doc(db, 'blocks/' + A + '__' + B), { blocker: A, blocked: B });
      await setDoc(doc(db, 'blocks/' + B + '__' + A), { blocker: B, blocked: A });
      await setDoc(doc(db, 'posts/mine'), {
        authorUid: A, audience: [A, C], createdAt: serverTimestamp(),
        likeCount: 0, commentCount: 1,
      });
      await setDoc(doc(db, 'posts/theirs'), {
        authorUid: C, audience: [A, C], createdAt: serverTimestamp(),
        likeCount: 1, commentCount: 1,
      });
      await setDoc(doc(db, 'posts/theirs/comments/mine'), {
        authorUid: A, audience: [A, C], text: 'hi',
        createdAt: serverTimestamp(),
      });
    });
  });

  it('their own space, whatever is under it', async () => {
    const db = as(A);
    await assertSucceeds(deleteDoc(doc(db, 'users/' + A + '/meta/profile')));
    await assertSucceeds(deleteDoc(doc(db, 'users/' + A + '/tasks/t1')));
    await assertSucceeds(deleteDoc(doc(db, 'users/' + A + '/likes/p_c')));
  });

  it('their public profile and both halves of the friend mirror', async () => {
    const db = as(A);
    await assertSucceeds(
      deleteDoc(doc(db, 'publicProfiles/' + A + '/friends/' + C)),
    );
    // The half in the FRIEND's document — the one a stranger could never
    // touch — because unfriending has always cleared both.
    await assertSucceeds(
      deleteDoc(doc(db, 'publicProfiles/' + C + '/friends/' + A)),
    );
    await assertSucceeds(deleteDoc(doc(db, 'publicProfiles/' + A)));
  });

  it('the friendship, from either side', async () => {
    await assertSucceeds(
      deleteDoc(doc(as(A), 'friendships/' + pairId(A, C))),
    );
  });

  it('the blocks they placed, and NOT the ones placed on them', async () => {
    const db = as(A);
    await assertSucceeds(deleteDoc(doc(db, 'blocks/' + A + '__' + B)));
    // Left behind by decision: B's block on A is B's, and deleting it would
    // let a departing account clear itself off somebody else's list.
    await assertFails(deleteDoc(doc(db, 'blocks/' + B + '__' + A)));
  });

  it('their own posts and their own comments, never anyone else\'s', async () => {
    const db = as(A);
    await assertSucceeds(deleteDoc(doc(db, 'posts/theirs/comments/mine')));
    await assertSucceeds(deleteDoc(doc(db, 'posts/mine')));
    await assertFails(deleteDoc(doc(db, 'posts/theirs')));
  });

  it('a stranger may delete none of it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'publicProfiles/' + A), { handle: 'ada', hours: 1 });
      await setDoc(doc(db, 'posts/again'), {
        authorUid: A, audience: [A, C], createdAt: serverTimestamp(),
        likeCount: 0, commentCount: 0,
      });
    });
    const db = as(D);
    await assertFails(deleteDoc(doc(db, 'publicProfiles/' + A)));
    await assertFails(deleteDoc(doc(db, 'posts/again')));
    await assertFails(deleteDoc(doc(db, 'users/' + A + '/meta/profile')));
  });
});

describe('the queries a leaving account runs', () => {
  /**
   * The deletes were tested and the QUERIES that find them were not, so a
   * query the rules refuse outright went to a device: every deletion failed
   * at the first statement, on a full account and an empty one alike.
   *
   * These are the cascade's own reads, run as the account that is leaving,
   * against the real rules. The Dart suite drives a fake Firestore, which
   * evaluates no rules at all, so this is the only place they can be
   * checked.
   *
   * A is leaving. C is their friend.
   */
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'users/' + A + '/likes/theirs'), { at: 1 });
      await setDoc(doc(db, 'users/' + A + '/photos/ph1'), {
        storagePath: 'users/' + A + '/photos/ph1.jpg',
      });
      await setDoc(doc(db, 'users/' + A + '/meta/profile'), { username: 'ada' });
      await setDoc(doc(db, 'publicProfiles/' + A), { handle: 'ada', hours: 1 });
      await setDoc(doc(db, 'publicProfiles/' + A + '/friends/' + C), { since: 1 });
      await setDoc(doc(db, 'friendships/' + pairId(A, C)), {
        users: [A, C], requestedBy: A, status: 'accepted',
      });
      await setDoc(doc(db, 'blocks/' + A + '__' + B), { blocker: A, blocked: B });
      await setDoc(doc(db, 'posts/mine'), {
        authorUid: A, audience: [A, C], createdAt: 1,
        likeCount: 0, commentCount: 1,
      });
      await setDoc(doc(db, 'posts/theirs'), {
        authorUid: C, audience: [A, C], createdAt: 2,
        likeCount: 1, commentCount: 1,
      });
      await setDoc(doc(db, 'posts/theirs/comments/mine'), {
        authorUid: A, audience: [A, C], text: 'hi', createdAt: 3,
      });
    });
  });

  /** AccountCascade.run's first statement, and FirestoreAudiences.mine's. */
  function authoredPosts(uid) {
    return query(
      collection(as(uid), 'posts'),
      where('authorUid', '==', uid),
      where('audience', 'array-contains', uid),
      orderBy('createdAt', 'desc'),
    );
  }

  it('their own posts — authorUid AND audience', async () => {
    const snap = await assertSucceeds(getDocs(authoredPosts(A)));
    assert.deepEqual(snap.docs.map((d) => d.id), ['mine']);
  });

  it('the same query on an account with no posts at all', async () => {
    // The shape is what the rules judge, not the result: a query they
    // refuse fails just as hard when it would have returned nothing, which
    // is why an empty brand-new account failed exactly like a full one.
    const snap = await assertSucceeds(getDocs(authoredPosts(D)));
    assert.equal(snap.size, 0);
  });

  it('their comments, wherever they are', async () => {
    const snap = await assertSucceeds(getDocs(query(
      collectionGroup(as(A), 'comments'),
      where('authorUid', '==', A),
    )));
    assert.deepEqual(snap.docs.map((d) => d.ref.path),
      ['posts/theirs/comments/mine']);
  });

  it('their likes', async () => {
    const snap = await assertSucceeds(
      getDocs(collection(as(A), 'users/' + A + '/likes')),
    );
    assert.deepEqual(snap.docs.map((d) => d.id), ['theirs']);
  });

  it('their photos, for the Storage paths', async () => {
    const snap = await assertSucceeds(
      getDocs(collection(as(A), 'users/' + A + '/photos')),
    );
    assert.equal(snap.size, 1);
  });

  it('the handle to give back', async () => {
    const snap = await assertSucceeds(
      getDoc(doc(as(A), 'users/' + A + '/meta/profile')),
    );
    assert.equal(snap.data().username, 'ada');
  });

  it('their own friend mirror', async () => {
    const snap = await assertSucceeds(
      getDocs(collection(as(A), 'publicProfiles/' + A + '/friends')),
    );
    assert.deepEqual(snap.docs.map((d) => d.id), [C]);
  });

  it('their friendships', async () => {
    const snap = await assertSucceeds(getDocs(query(
      collection(as(A), 'friendships'),
      where('users', 'array-contains', A),
    )));
    assert.equal(snap.size, 1);
  });

  it('the blocks they placed', async () => {
    const snap = await assertSucceeds(getDocs(query(
      collection(as(A), 'blocks'),
      where('blocker', '==', A),
    )));
    assert.deepEqual(snap.docs.map((d) => d.id), [A + '__' + B]);
  });

  it('every one of those on an account that has nothing', async () => {
    // A brand-new account: the same reads, all of them empty, none of them
    // refused. This is the case the device failed on.
    await assertSucceeds(getDocs(authoredPosts(D)));
    await assertSucceeds(getDocs(query(
      collectionGroup(as(D), 'comments'),
      where('authorUid', '==', D),
    )));
    await assertSucceeds(getDocs(collection(as(D), 'users/' + D + '/likes')));
    await assertSucceeds(getDocs(collection(as(D), 'users/' + D + '/photos')));
    await assertSucceeds(getDoc(doc(as(D), 'users/' + D + '/meta/profile')));
    await assertSucceeds(
      getDocs(collection(as(D), 'publicProfiles/' + D + '/friends')),
    );
    await assertSucceeds(getDocs(query(
      collection(as(D), 'friendships'),
      where('users', 'array-contains', D),
    )));
    await assertSucceeds(getDocs(query(
      collection(as(D), 'blocks'),
      where('blocker', '==', D),
    )));
  });

  it('and the shape that was shipped is refused, for the author too', async () => {
    // The bug, pinned: authorUid alone, asked by the author themself.
    await assertFails(getDocs(query(
      collection(as(A), 'posts'),
      where('authorUid', '==', A),
      orderBy('createdAt', 'desc'),
    )));
    await assertFails(getDocs(query(
      collection(as(A), 'posts'),
      where('authorUid', '==', A),
    )));
  });
});

describe('the prune, end to end', () => {
  /**
   * The prune's own query was refused by the rules, its failures are
   * swallowed by design, and nothing noticed: a blocked person was never
   * taken out of the audience of posts that already existed, so they kept
   * seeing them. This is the whole flow against the real rules — the query
   * that finds A's posts, the arrayRemove that prunes B out of them, and
   * the proof that B can no longer read what they used to.
   */
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/old1'), {
        authorUid: A, audience: [A, B, C], createdAt: 1,
      });
      await setDoc(doc(db, 'posts/old2'), {
        authorUid: A, audience: [A, B, C], createdAt: 2,
      });
      // Somebody else's post B is in, which A must not touch.
      await setDoc(doc(db, 'posts/theirs'), {
        authorUid: C, audience: [A, B, C], createdAt: 3,
      });
      // A's comment under C's post, which carries its own audience.
      await setDoc(doc(db, 'posts/theirs/comments/mine'), {
        authorUid: A, audience: [A, B, C], text: 'hi', createdAt: 4,
      });
    });
  });

  /** What B can see of A's posts, which is B's feed, filtered. */
  async function feedOf(uid) {
    const snap = await getDocs(query(
      collection(as(uid), 'posts'),
      where('audience', 'array-contains', uid),
      orderBy('createdAt', 'desc'),
    ));
    return snap.docs.map((d) => d.id);
  }

  it('before: B sees both of A\'s posts', async () => {
    assert.deepEqual(await feedOf(B), ['theirs', 'old2', 'old1']);
  });

  it('the prune finds A\'s posts and A\'s comments, and prunes B out', async () => {
    // ONE instance: a batch and the references in it have to come from the
    // same Firestore, which `as()` mints fresh on every call.
    const db = as(A);
    // Exactly what FirestoreAudiences.mine() runs.
    const posts = await assertSucceeds(getDocs(query(
      collection(db, 'posts'),
      where('authorUid', '==', A),
      where('audience', 'array-contains', A),
      orderBy('createdAt', 'desc'),
    )));
    const comments = await assertSucceeds(getDocs(query(
      collectionGroup(db, 'comments'),
      where('authorUid', '==', A),
    )));
    const paths = [
      ...posts.docs.map((d) => d.ref.path),
      ...comments.docs.map((d) => d.ref.path),
    ];
    assert.deepEqual(paths.sort(),
      ['posts/old1', 'posts/old2', 'posts/theirs/comments/mine']);

    // And the write the pruner makes: one batch of arrayRemove.
    const batch = writeBatch(db);
    for (const path of paths) {
      batch.update(doc(db, path), { audience: arrayRemove(B) });
    }
    await assertSucceeds(batch.commit());
  });

  it('after: B cannot read A\'s posts, and C still can', async () => {
    assert.deepEqual(await feedOf(B), ['theirs']);
    assert.deepEqual(await feedOf(C), ['theirs', 'old2', 'old1']);
    // Not even one by one, which is the thing a feed query cannot prove.
    await assertFails(getDoc(doc(as(B), 'posts/old1')));
    await assertSucceeds(getDoc(doc(as(C), 'posts/old1')));
  });

  it('and B is out of A\'s comment under somebody else\'s post', async () => {
    const snap = await getDoc(doc(as(A), 'posts/theirs/comments/mine'));
    assert.equal(snap.data().audience.includes(B), false);
    assert.equal(snap.data().audience.includes(C), true);
  });

  it('C\'s own post was left alone', async () => {
    const snap = await getDoc(doc(as(C), 'posts/theirs'));
    assert.deepEqual(snap.data().audience, [A, B, C]);
  });

  it('a prune run twice removes nothing more', async () => {
    const db = as(A);
    const batch = writeBatch(db);
    batch.update(doc(db, 'posts/old1'), { audience: arrayRemove(B) });
    await assertSucceeds(batch.commit());
    const snap = await getDoc(doc(db, 'posts/old1'));
    assert.deepEqual(snap.data().audience, [A, C]);
  });
});

describe('who invited whom', () => {
  /**
   * One document per invited account, written once by that account.
   *
   * The handle travels with the uid so the pair can be read back without a
   * second lookup, and the rule checks the two against the usernames index
   * — an invite cannot credit somebody who does not hold that handle.
   */
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'usernames/ada'), { uid: A });
      await setDoc(doc(db, 'usernames/cass'), { uid: C });
    });
  });

  /** What the app writes when B says A invited them. */
  function invite(fields = {}) {
    return {
      invitedBy: A,
      invitedByHandle: 'ada',
      at: serverTimestamp(),
      ...fields,
    };
  }

  it('the invited account writes its own, once', async () => {
    await assertSucceeds(setDoc(doc(as(B), 'invites/' + B), invite()));
    // And only the once: it is a fact about how they arrived, not a
    // setting. A second create is an update of an existing document.
    await assertFails(setDoc(doc(as(B), 'invites/' + B), invite({
      invitedBy: C, invitedByHandle: 'cass',
    })));
    await assertFails(
      updateDoc(doc(as(B), 'invites/' + B), { invitedBy: C }),
    );
  });

  it('and reads it back; nobody else can', async () => {
    await assertSucceeds(getDoc(doc(as(B), 'invites/' + B)));
    await assertFails(getDoc(doc(as(A), 'invites/' + B)));
    await assertFails(getDoc(doc(as(D), 'invites/' + B)));
  });

  it('nobody can write an invite for somebody else', async () => {
    await assertFails(setDoc(doc(as(A), 'invites/' + D), invite()));
  });

  it('a guest cannot: there is no account for it to belong to', async () => {
    const guest = env
      .authenticatedContext(D, { firebase: { sign_in_provider: 'anonymous' } })
      .firestore();
    await assertFails(setDoc(doc(guest, 'invites/' + D), invite()));
  });

  it('the handle and the uid have to be the same person', async () => {
    // cass's handle, ada's uid.
    await assertFails(setDoc(doc(as(D), 'invites/' + D), invite({
      invitedByHandle: 'cass',
    })));
    // A handle nobody holds.
    await assertFails(setDoc(doc(as(D), 'invites/' + D), invite({
      invitedByHandle: 'nobody',
    })));
  });

  it('you cannot have invited yourself', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'usernames/dee'), { uid: D });
    });
    await assertFails(setDoc(doc(as(D), 'invites/' + D), invite({
      invitedBy: D, invitedByHandle: 'dee',
    })));
  });

  it('exactly those three fields, and the server\'s own clock', async () => {
    await assertFails(setDoc(doc(as(D), 'invites/' + D), invite({
      extra: 'no',
    })));
    await assertFails(setDoc(doc(as(D), 'invites/' + D), {
      invitedBy: A,
      at: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(as(D), 'invites/' + D), invite({
      at: new Date(2000, 1, 1),
    })));
  });

  it('and deleting it is theirs alone — which is what leaving does', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'invites/' + C), {
        invitedBy: A, invitedByHandle: 'ada', at: new Date(),
      });
    });
    await assertFails(deleteDoc(doc(as(A), 'invites/' + C)));
    await assertSucceeds(deleteDoc(doc(as(C), 'invites/' + C)));
  });
});

describe('what a deletion may reach', () => {
  // A: the post's author. B and C: two people the post reaches.
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/p1'), { authorUid: A, audience: [A, B, C], createdAt: 1, likeCount: 2 });
      await setDoc(doc(db, 'posts/p1/likes/' + B), { at: 1 });
      await setDoc(doc(db, 'posts/p1/likes/' + C), { at: 2 });
      await setDoc(doc(db, 'users/' + B + '/likes/p1'), { createdAt: 1 });
      await setDoc(doc(db, 'users/' + C + '/likes/p1'), { createdAt: 2 });
      await setDoc(doc(db, 'posts/p1/comments/c1'), { authorUid: B, audience: [A, B, C], text: 't', createdAt: 1 });
      await setDoc(doc(db, 'posts/p1/comments/c2'), { authorUid: C, audience: [A, B, C], text: 'r', createdAt: 2, parentId: 'c1' });
      // Somebody else's post, with a like of B's on it.
      await setDoc(doc(db, 'posts/p2'), { authorUid: C, audience: [A, B, C], createdAt: 2, likeCount: 1 });
      await setDoc(doc(db, 'posts/p2/likes/' + B), { at: 1 });
      await setDoc(doc(db, 'users/' + B + '/likes/p2'), { createdAt: 1 });
    });
  });

  it('a liker takes their own like, its copy under the post and the count, in one batch', async () => {
    const db = as(B);
    const batch = writeBatch(db);
    batch.delete(doc(db, 'users/' + B + '/likes/p2'));
    batch.delete(doc(db, 'posts/p2/likes/' + B));
    batch.update(doc(db, 'posts/p2'), { likeCount: 0 });
    await assertSucceeds(batch.commit());
  });

  it("the post's author may clear a like, a comment and a reply under their own post", async () => {
    const db = as(A);
    await assertSucceeds(deleteDoc(doc(db, 'posts/p1/likes/' + B)));
    await assertSucceeds(deleteDoc(doc(db, 'posts/p1/comments/c2')));
    await assertSucceeds(deleteDoc(doc(db, 'posts/p1/comments/c1')));
  });

  it("the post's author may not take the mirror on its own, while the like it mirrors is still there", async () => {
    await assertFails(deleteDoc(doc(as(A), 'users/' + C + '/likes/p1')));
    // Still there, and still C's.
    await assertSucceeds(getDoc(doc(as(C), 'users/' + C + '/likes/p1')));
  });

  it('the mirror goes in the same batch as the like it mirrors', async () => {
    const db = as(A);
    const batch = writeBatch(db);
    batch.delete(doc(db, 'posts/p1/likes/' + C));
    batch.delete(doc(db, 'users/' + C + '/likes/p1'));
    await assertSucceeds(batch.commit());
  });

  it("the post's author may remove the liker's own mirror once the like is gone — that document and no other", async () => {
    const db = as(A);
    // B's like under the post was cleared by the test above, so the
    // mirror is now the author's to take.
    await assertSucceeds(deleteDoc(doc(db, 'users/' + B + '/likes/p1')));
    // Only that one document: nothing else of B's is reachable.
    await assertFails(getDoc(doc(db, 'users/' + B + '/likes/p1')));
    await assertFails(setDoc(doc(db, 'users/' + B + '/likes/p1'), { createdAt: 9 }));
    await assertFails(deleteDoc(doc(db, 'users/' + B + '/meta/profile')));
    await assertFails(deleteDoc(doc(db, 'users/' + B + '/tasks/t1')));
    await assertFails(getDoc(doc(db, 'users/' + B + '/likes/p2')));
  });

  it('a mirror for somebody ELSE\'s post is not the author\'s to touch', async () => {
    // p2 is C's post, so A may not reach B's mirror of it.
    await assertFails(deleteDoc(doc(as(A), 'users/' + B + '/likes/p2')));
  });

  it('a stranger may clear nothing of it', async () => {
    await assertFails(deleteDoc(doc(as(D), 'posts/p1/likes/' + C)));
    await assertFails(deleteDoc(doc(as(D), 'users/' + C + '/likes/p1')));
    await assertFails(deleteDoc(doc(as(B), 'users/' + C + '/likes/p1')));
  });

  it('a reader of the post may not clear somebody else\'s like or comment on it', async () => {
    // B is in the audience but is not the author.
    await assertFails(deleteDoc(doc(as(B), 'posts/p1/likes/' + C)));
    await assertFails(deleteDoc(doc(as(B), 'users/' + C + '/likes/p1')));
  });
});

describe("a post's author reading the comments under it", () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/p1'), { authorUid: A, audience: [A, B, C], createdAt: 1, likeCount: 0, commentCount: 2 });
      await setDoc(doc(db, 'posts/p1/comments/c1'), { authorUid: B, audience: [A, B, C], text: 'seen', createdAt: 1 });
      // B narrowed this one away from the author. The per-document rule
      // hides it from A; the author's own rule does not.
      await setDoc(doc(db, 'posts/p1/comments/c2'), { authorUid: B, audience: [B, C], text: 'hidden', createdAt: 2 });
      await setDoc(doc(db, 'posts/p2'), { authorUid: C, audience: [A, C], createdAt: 2, likeCount: 0, commentCount: 0 });
    });
  });

  it('lists every comment under it, unfiltered, including one narrowed away from them', async () => {
    const snap = await assertSucceeds(getDocs(collection(as(A), 'posts/p1/comments')));
    assert.equal(snap.size, 2);
    assert.deepEqual(snap.docs.map((d) => d.id).sort(), ['c1', 'c2']);
  });

  it('and reads one of them on its own', async () => {
    await assertSucceeds(getDoc(doc(as(A), 'posts/p1/comments/c2')));
  });

  it('somebody who is neither the author nor in the comment may not list them', async () => {
    // D is a stranger to the post entirely.
    await assertFails(getDocs(collection(as(D), 'posts/p1/comments')));
    await assertFails(getDoc(doc(as(D), 'posts/p1/comments/c1')));
    // C is in the post's audience but is not its author, so the per-document
    // rule is all they have: a plain list is still refused.
    await assertFails(getDocs(collection(as(C), 'posts/p1/comments')));
    // With the filter the app's own reader carries, it works for them.
    await assertSucceeds(getDocs(query(
      collection(as(C), 'posts/p1/comments'), where('audience', 'array-contains', C), orderBy('createdAt'))));
  });

  it("and not over somebody else's post", async () => {
    await assertFails(getDocs(collection(as(A), 'posts/p2/comments')));
  });
});

describe('the notices an account leaves in other people\'s inboxes', () => {
  before(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      await setDoc(doc(db, 'notifications/' + A + '/items/n1'), { type: 'like', actorUid: B, actorHandle: 'b', postId: 'p1', at: 1 });
      await setDoc(doc(db, 'notifications/' + C + '/items/n2'), { type: 'like', actorUid: B, actorHandle: 'b', postId: 'p1', at: 2 });
      await setDoc(doc(db, 'notifications/' + A + '/items/n3'), { type: 'like', actorUid: C, actorHandle: 'c', postId: 'p1', at: 3 });
    });
  });

  it('the actor can find every notice they caused, wherever it landed', async () => {
    const q = query(collectionGroup(as(B), 'items'), where('actorUid', '==', B));
    const snap = await assertSucceeds(getDocs(q));
    assert.equal(snap.size, 2);
  });

  it('and take them back', async () => {
    await assertSucceeds(deleteDoc(doc(as(B), 'notifications/' + A + '/items/n1')));
    await assertSucceeds(deleteDoc(doc(as(B), 'notifications/' + C + '/items/n2')));
  });

  it('the recipient still has theirs, and can still clear it', async () => {
    await assertSucceeds(getDoc(doc(as(A), 'notifications/' + A + '/items/n3')));
    await assertSucceeds(deleteDoc(doc(as(A), 'notifications/' + A + '/items/n3')));
  });

  it('nobody else reaches a notice they neither received nor caused', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'notifications/' + A + '/items/n4'), { type: 'like', actorUid: C, actorHandle: 'c', postId: 'p1', at: 4 });
    });
    await assertFails(getDoc(doc(as(B), 'notifications/' + A + '/items/n4')));
    await assertFails(deleteDoc(doc(as(B), 'notifications/' + A + '/items/n4')));
    await assertFails(getDocs(query(collectionGroup(as(B), 'items'), where('actorUid', '==', C))));
    // And the whole inbox is still not browsable by an outsider.
    await assertFails(getDocs(collection(as(B), 'notifications/' + A + '/items')));
  });

  it('a notice is still never updated, by anyone', async () => {
    await assertFails(updateDoc(doc(as(B), 'notifications/' + A + '/items/n4'), { actorHandle: 'x' }));
    await assertFails(updateDoc(doc(as(A), 'notifications/' + A + '/items/n4'), { actorHandle: 'x' }));
  });
});

/**
 * End to end, against the real rules: the two deletions the app runs, in
 * the order and the batch shapes the Dart runs them in. Not a rule
 * checked in isolation — the whole sequence, as a client with no special
 * powers, asserting that what should go has gone and what should stay
 * has stayed.
 */
const BATCH = 450;

/// deletePostContents, as lib/features/feed/posts_repository.dart has it:
/// every read first, then batches that carry their own counter.
async function deletePostContents(db, postId) {
  const postRef = doc(db, 'posts/' + postId);
  const post = await getDoc(postRef);
  if (!post.exists()) return;
  const countsLikes = post.get('likeCount') !== undefined;
  const countsComments = post.get('commentCount') !== undefined;
  const likes = (await getDocs(collection(db, 'posts/' + postId + '/likes'))).docs;
  const comments = (await getDocs(collection(db, 'posts/' + postId + '/comments'))).docs;

  const likesPerBatch = Math.floor((BATCH - 1) / 2);
  for (let i = 0; i < likes.length; i += likesPerBatch) {
    const page = likes.slice(i, i + likesPerBatch);
    const batch = writeBatch(db);
    for (const like of page) {
      batch.delete(like.ref);
      batch.delete(doc(db, 'users/' + like.id + '/likes/' + postId));
    }
    if (countsLikes) batch.update(postRef, { likeCount: increment(-page.length) });
    await batch.commit();
  }
  const commentsPerBatch = BATCH - 1;
  for (let i = 0; i < comments.length; i += commentsPerBatch) {
    const page = comments.slice(i, i + commentsPerBatch);
    const batch = writeBatch(db);
    for (const c of page) batch.delete(c.ref);
    if (countsComments) batch.update(postRef, { commentCount: increment(-page.length) });
    await batch.commit();
  }
}

async function deletePost(db, postId) {
  await deletePostContents(db, postId);
  await deleteDoc(doc(db, 'posts/' + postId));
}

describe('deleting a post, end to end against the rules', () => {
  /// [like] a friend's like, [perPost] its copy under the post (an old
  /// like has none), [comment] a friend's comment, [reply] a friend's
  /// reply to it, [counters] whether the post carries them at all.
  async function makePost(id, { like = true, perPost = true, comment = true, reply = false, counters = true } = {}) {
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/' + id), {
        authorUid: A, audience: [A, B], createdAt: 1,
        ...(counters ? { likeCount: like ? 1 : 0, commentCount: (comment ? 1 : 0) + (reply ? 1 : 0) } : {}),
      });
      if (like) {
        await setDoc(doc(db, 'users/' + B + '/likes/' + id), { createdAt: 1 });
        if (perPost) await setDoc(doc(db, 'posts/' + id + '/likes/' + B), { at: 1 });
      }
      if (comment) {
        await setDoc(doc(db, 'posts/' + id + '/comments/c1'), { authorUid: B, audience: [A, B], text: 'nice', createdAt: 1 });
      }
      if (reply) {
        await setDoc(doc(db, 'posts/' + id + '/comments/r1'), { authorUid: B, audience: [A, B], text: 'more', createdAt: 2, parentId: 'c1' });
      }
    });
  }

  /// Nothing of the post left anywhere, checked with the rules off.
  async function assertGone(id) {
    await seed(async (db) => {
      assert.equal((await getDoc(doc(db, 'posts/' + id))).exists(), false, 'the post');
      assert.equal((await getDocs(collection(db, 'posts/' + id + '/likes'))).size, 0, 'its likes');
      assert.equal((await getDocs(collection(db, 'posts/' + id + '/comments'))).size, 0, 'its comments');
      assert.equal((await getDoc(doc(db, 'users/' + B + '/likes/' + id))).exists(), false, "the liker's mirror");
    });
  }

  beforeEach(async () => { await env.clearFirestore(); });

  it('a like and a comment from a friend — the shape that failed on the device', async () => {
    await makePost('p1');
    await assertSucceeds(deletePost(as(A), 'p1'));
    await assertGone('p1');
  });

  it('with a reply as well', async () => {
    await makePost('p2', { reply: true });
    await assertSucceeds(deletePost(as(A), 'p2'));
    await assertGone('p2');
  });

  it('a like and no comments', async () => {
    await makePost('p3', { comment: false });
    await assertSucceeds(deletePost(as(A), 'p3'));
    await assertGone('p3');
  });

  it('an older like: a mirror with no copy under the post', async () => {
    await makePost('p4', { perPost: false });
    await assertSucceeds(deletePost(as(A), 'p4'));
    // The mirror of a like the post never kept a copy of cannot be found
    // by the author, so it stays — naming a post that no longer exists.
    await seed(async (db) => {
      assert.equal((await getDoc(doc(db, 'posts/p4'))).exists(), false);
      assert.equal((await getDoc(doc(db, 'users/' + B + '/likes/p4'))).exists(), true);
    });
  });

  it('nothing under it at all', async () => {
    await makePost('p5', { like: false, comment: false });
    await assertSucceeds(deletePost(as(A), 'p5'));
    await assertGone('p5');
  });

  it('a post from before counters existed', async () => {
    await makePost('p6', { counters: false });
    await assertSucceeds(deletePost(as(A), 'p6'));
    await assertGone('p6');
  });

  it('a comment the writer narrowed away from the author still goes', async () => {
    await makePost('p7', { comment: false });
    await seed(async (db) => {
      await setDoc(doc(db, 'posts/p7/comments/hidden'), { authorUid: B, audience: [B], text: 'x', createdAt: 1 });
    });
    await assertSucceeds(deletePost(as(A), 'p7'));
    await assertGone('p7');
  });

  it('halfway through, the counts still match what is under the post', async () => {
    await makePost('p8');
    const db = as(A);
    // The likes batch only: what an interruption before the comments
    // leaves behind.
    const postRef = doc(db, 'posts/p8');
    const batch = writeBatch(db);
    batch.delete(doc(db, 'posts/p8/likes/' + B));
    batch.delete(doc(db, 'users/' + B + '/likes/p8'));
    batch.update(postRef, { likeCount: increment(-1) });
    await assertSucceeds(batch.commit());
    await seed(async (raw) => {
      const p = await getDoc(doc(raw, 'posts/p8'));
      assert.equal(p.get('likeCount'), 0);
      assert.equal((await getDocs(collection(raw, 'posts/p8/likes'))).size, 0);
      assert.equal(p.get('commentCount'), 1);
      assert.equal((await getDocs(collection(raw, 'posts/p8/comments'))).size, 1);
    });
    // And running the whole thing again finishes it.
    await assertSucceeds(deletePost(as(A), 'p8'));
    await assertGone('p8');
  });

  it('nobody else can run it', async () => {
    await makePost('p9');
    await assertFails(deletePost(as(B), 'p9'));
    await assertFails(deletePost(as(D), 'p9'));
    await seed(async (db) => {
      assert.equal((await getDoc(doc(db, 'posts/p9'))).exists(), true);
    });
  });
});

describe('deleting an account, end to end against the rules', () => {
  // ME is leaving. They liked and commented on a friend's post, were
  // liked and commented on in return, and left notices in two inboxes.
  const ME = A;
  const FRIEND = B;
  const OTHER = C;

  beforeEach(async () => {
    await env.clearFirestore();
    await seed(async (db) => {
      // Their own space.
      await setDoc(doc(db, 'users/' + ME + '/meta/profile'), { username: 'ada' });
      await setDoc(doc(db, 'users/' + ME + '/tasks/t1'), { name: 'Golf' });
      await setDoc(doc(db, 'usernames/ada'), { uid: ME });
      await setDoc(doc(db, 'publicProfiles/' + ME), { handle: 'ada', hours: 3 });
      await setDoc(doc(db, 'publicProfiles/' + ME + '/friends/' + FRIEND), { since: 1 });
      await setDoc(doc(db, 'publicProfiles/' + FRIEND + '/friends/' + ME), { since: 1 });
      await setDoc(doc(db, 'friendships/' + pairId(ME, FRIEND)), {
        users: [ME, FRIEND].sort(), requestedBy: ME, status: 'accepted',
      });
      await setDoc(doc(db, 'invites/' + ME), { invitedBy: FRIEND, invitedByHandle: 'cass', at: 1 });

      // A post of theirs, liked and commented on by the friend.
      await setDoc(doc(db, 'posts/mine'), {
        authorUid: ME, audience: [ME, FRIEND], createdAt: 2, likeCount: 1, commentCount: 1,
      });
      await setDoc(doc(db, 'posts/mine/likes/' + FRIEND), { at: 1 });
      await setDoc(doc(db, 'users/' + FRIEND + '/likes/mine'), { createdAt: 1 });
      await setDoc(doc(db, 'posts/mine/comments/theirs'), {
        authorUid: FRIEND, audience: [ME, FRIEND], text: 'nice', createdAt: 1,
      });

      // The friend's post, which they liked and commented on.
      await setDoc(doc(db, 'posts/theirs'), {
        authorUid: FRIEND, audience: [ME, FRIEND], createdAt: 1, likeCount: 1, commentCount: 1,
      });
      await setDoc(doc(db, 'posts/theirs/likes/' + ME), { at: 1 });
      await setDoc(doc(db, 'users/' + ME + '/likes/theirs'), { createdAt: 1 });
      await setDoc(doc(db, 'posts/theirs/comments/by-me'), {
        authorUid: ME, audience: [ME, FRIEND], text: 'ta', createdAt: 1,
      });

      // Notices: two they caused, one they received, one of neither.
      await setDoc(doc(db, 'notifications/' + FRIEND + '/items/n1'), { type: 'like', actorUid: ME, actorHandle: 'ada', postId: 'theirs', at: 1 });
      await setDoc(doc(db, 'notifications/' + OTHER + '/items/n2'), { type: 'like', actorUid: ME, actorHandle: 'ada', postId: 'x', at: 2 });
      await setDoc(doc(db, 'notifications/' + ME + '/items/n3'), { type: 'like', actorUid: FRIEND, actorHandle: 'cass', postId: 'mine', at: 3 });
      await setDoc(doc(db, 'notifications/' + OTHER + '/items/n4'), { type: 'like', actorUid: FRIEND, actorHandle: 'cass', postId: 'y', at: 4 });
    });
  });

  /// AccountCascade.run, in its order, as a client.
  async function runCascade(db, uid) {
    const myPosts = await getDocs(query(collection(db, 'posts'),
      where('authorUid', '==', uid), where('audience', 'array-contains', uid), orderBy('createdAt', 'desc')));
    const myPostIds = new Set(myPosts.docs.map((d) => d.id));
    const myComments = (await getDocs(query(collectionGroup(db, 'comments'), where('authorUid', '==', uid)))).docs;
    const handle = (await getDoc(doc(db, 'users/' + uid + '/meta/profile'))).get('username') ?? '';

    // Their inbox, then the notices they left elsewhere.
    for (const d of (await getDocs(collection(db, 'notifications/' + uid + '/items'))).docs) {
      await deleteDoc(d.ref);
    }
    for (const d of (await getDocs(query(collectionGroup(db, 'items'), where('actorUid', '==', uid)))).docs) {
      if (d.ref.parent.parent.id !== uid) await deleteDoc(d.ref);
    }

    // Their likes: mirror, copy under the post, and the count, together.
    for (const like of (await getDocs(collection(db, 'users/' + uid + '/likes'))).docs) {
      const postId = like.id;
      if (myPostIds.has(postId)) { await deleteDoc(like.ref); continue; }
      const batch = writeBatch(db);
      batch.delete(like.ref);
      batch.delete(doc(db, 'posts/' + postId + '/likes/' + uid));
      batch.update(doc(db, 'posts/' + postId), { likeCount: increment(-1) });
      await batch.commit();
    }

    // Their comments, wherever they are, with the counts they hold up.
    for (const c of myComments) {
      const postId = c.ref.path.split('/')[1];
      const batch = writeBatch(db);
      batch.delete(c.ref);
      if (!myPostIds.has(postId)) {
        batch.update(doc(db, 'posts/' + postId), { commentCount: increment(-1) });
      }
      await batch.commit();
    }

    // Their posts, contents first.
    for (const id of myPostIds) await deletePost(db, id);

    // The mirror both ways, the friendships, the public profile, the
    // invite, the handle, then their own space.
    for (const f of (await getDocs(collection(db, 'publicProfiles/' + uid + '/friends'))).docs) {
      await deleteDoc(doc(db, 'publicProfiles/' + f.id + '/friends/' + uid));
      await deleteDoc(f.ref);
    }
    for (const f of (await getDocs(query(collection(db, 'friendships'), where('users', 'array-contains', uid)))).docs) {
      await deleteDoc(f.ref);
    }
    await deleteDoc(doc(db, 'publicProfiles/' + uid));
    await deleteDoc(doc(db, 'invites/' + uid));
    if (handle) await deleteDoc(doc(db, 'usernames/' + handle));
    for (const name of ['meta', 'tasks', 'habitDays', 'photos', 'collages', 'likes', 'hidden', 'sessions']) {
      for (const d of (await getDocs(collection(db, 'users/' + uid + '/' + name))).docs) await deleteDoc(d.ref);
    }
    await deleteDoc(doc(db, 'users/' + uid));
  }

  it('leaves nothing of theirs, and the counters right', async () => {
    await assertSucceeds(runCascade(as(ME), ME));
    await seed(async (db) => {
      // Theirs, gone.
      for (const path of [
        'users/' + ME, 'users/' + ME + '/meta/profile', 'users/' + ME + '/tasks/t1',
        'usernames/ada', 'publicProfiles/' + ME, 'publicProfiles/' + ME + '/friends/' + FRIEND,
        'publicProfiles/' + FRIEND + '/friends/' + ME, 'friendships/' + pairId(ME, FRIEND),
        'invites/' + ME, 'posts/mine', 'posts/mine/likes/' + FRIEND, 'posts/mine/comments/theirs',
        'users/' + FRIEND + '/likes/mine', 'posts/theirs/likes/' + ME, 'users/' + ME + '/likes/theirs',
        'posts/theirs/comments/by-me', 'notifications/' + ME + '/items/n3',
        'notifications/' + FRIEND + '/items/n1', 'notifications/' + OTHER + '/items/n2',
      ]) {
        assert.equal((await getDoc(doc(db, path))).exists(), false, path + ' should be gone');
      }
      // The friend's own things, untouched, and their counts put right.
      const theirs = await getDoc(doc(db, 'posts/theirs'));
      assert.equal(theirs.exists(), true);
      assert.equal(theirs.get('likeCount'), 0, 'the like came off the count');
      assert.equal(theirs.get('commentCount'), 0, 'and so did the comment');
      assert.equal((await getDocs(collection(db, 'posts/theirs/likes'))).size, 0);
      assert.equal((await getDocs(collection(db, 'posts/theirs/comments'))).size, 0);
      assert.equal((await getDoc(doc(db, 'notifications/' + OTHER + '/items/n4'))).exists(), true, 'not theirs to take');
    });
  });

  it('run again over a finished account, and nothing moves', async () => {
    await assertSucceeds(runCascade(as(ME), ME));
    await assertSucceeds(runCascade(as(ME), ME));
    await seed(async (db) => {
      const theirs = await getDoc(doc(db, 'posts/theirs'));
      assert.equal(theirs.get('likeCount'), 0, 'never twice');
      assert.equal(theirs.get('commentCount'), 0);
    });
  });

  it('nobody can run it over somebody else', async () => {
    await assertFails(runCascade(as(FRIEND), ME));
  });
});

/**
 * Storage. The share job writes every file of a post under the post's id —
 * `users/{uid}/posts/{postId}/0.jpg`, `cover.jpg`, `thumb.jpg` — which is one
 * segment deeper than the posts of old, `users/{uid}/posts/{file}`. A match
 * on `{file}` is ONE segment: it never matched the new paths, every upload
 * was refused as unauthorized, and no post could be shared. These tests put
 * the job's exact paths, as the job does.
 */
describe('storage: the share job\'s paths', () => {
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const meta = { contentType: 'image/jpeg' };
  function bucket(uid) { return env.authenticatedContext(uid).storage(); }

  it('the author may put a post\'s photos, cover and thumbnail under the post\'s id', async () => {
    const s = bucket(A);
    for (const name of ['0.jpg', '1.jpg', 'cover.jpg', 'thumb.jpg']) {
      await assertSucceeds(s.ref(`users/${A}/posts/post1/${name}`).put(jpeg, meta));
    }
  });

  it('a post\'s files are readable to anyone signed in, and to nobody who is not', async () => {
    await assertSucceeds(bucket(A).ref(`users/${A}/posts/read1/0.jpg`).put(jpeg, meta));
    await assertSucceeds(bucket(B).ref(`users/${A}/posts/read1/0.jpg`).getDownloadURL());
    await assertFails(env.unauthenticatedContext().storage().ref(`users/${A}/posts/read1/0.jpg`).getDownloadURL());
  });

  it('nobody else may write into someone\'s post space', async () => {
    await assertFails(bucket(B).ref(`users/${A}/posts/post2/0.jpg`).put(jpeg, meta));
    await assertFails(bucket(B).ref(`users/${A}/posts/post2/cover.jpg`).put(jpeg, meta));
  });

  it('a file that is not an image is refused', async () => {
    await assertFails(bucket(A).ref(`users/${A}/posts/post3/0.jpg`).put(jpeg, { contentType: 'text/plain' }));
  });

  it('the author may take a post\'s files down; nobody else may', async () => {
    await assertSucceeds(bucket(A).ref(`users/${A}/posts/del1/0.jpg`).put(jpeg, meta));
    await assertFails(bucket(B).ref(`users/${A}/posts/del1/0.jpg`).delete());
    await assertSucceeds(bucket(A).ref(`users/${A}/posts/del1/0.jpg`).delete());
  });

  it('a post from before, at the flat path, still reads and still comes down', async () => {
    await assertSucceeds(bucket(A).ref(`users/${A}/posts/old1.jpg`).put(jpeg, meta));
    await assertSucceeds(bucket(B).ref(`users/${A}/posts/old1.jpg`).getDownloadURL());
    await assertSucceeds(bucket(A).ref(`users/${A}/posts/old1.jpg`).delete());
  });

  it('the new shot\'s private copy is the owner\'s alone', async () => {
    await assertSucceeds(bucket(A).ref(`users/${A}/photos/t_1.jpg`).put(jpeg, meta));
    await assertFails(bucket(B).ref(`users/${A}/photos/t_1.jpg`).getDownloadURL());
    await assertFails(bucket(B).ref(`users/${A}/photos/t_2.jpg`).put(jpeg, meta));
  });

  // A post's files are readable to anyone signed in, so their names are
  // too; the private photos are the owner's alone, names included.
  it('the owner may list their posts, each post\'s folder and their private photos — the sweep a leaving account runs; nobody else lists the private photos', async () => {
    await assertSucceeds(bucket(A).ref(`users/${A}/posts/list1/0.jpg`).put(jpeg, meta));
    await assertSucceeds(bucket(A).ref(`users/${A}/photos/t_list.jpg`).put(jpeg, meta));
    const top = await assertSucceeds(bucket(A).ref(`users/${A}/posts`).listAll());
    assert.ok(top.prefixes.some((p) => p.name === 'list1'), 'the post\'s folder is a prefix under posts');
    const inner = await assertSucceeds(bucket(A).ref(`users/${A}/posts/list1`).listAll());
    assert.deepEqual(inner.items.map((i) => i.name), ['0.jpg']);
    await assertSucceeds(bucket(A).ref(`users/${A}/photos`).listAll());
    await assertFails(bucket(B).ref(`users/${A}/photos`).listAll());
  });
});
