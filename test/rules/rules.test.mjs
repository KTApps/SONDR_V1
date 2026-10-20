import { strict as assert } from 'node:assert';
import { after, before, describe, it } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  collection, doc, getDocs, orderBy, query, setDoc, updateDoc, where,
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
