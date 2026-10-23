import { strict as assert } from 'node:assert';
import { after, before, describe, it } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, limit, orderBy, query,
  serverTimestamp, setDoc, updateDoc, where, writeBatch,
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

  it('widening an audience is denied', async () => {
    await assertFails(
      updateDoc(doc(as(A), 'posts/p1/comments/c2'), { audience: [A, B, C] }));
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

  it('the same query without the audience filter is denied outright', async () => {
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
