# Handling a report

Someone can report a post, a comment or a person from inside the app. Every
report lands in one place, and we have told Apple we look at them within 24
hours. This is how.

## Where they arrive

[Firestore → the `reports` collection](https://console.firebase.google.com/project/sondr-cd439/firestore/data/~2Freports)

Click **Query builder** → order by `createdAt`, **descending**, to put the
newest first.

One report looks like this:

| Field | What it is |
| --- | --- |
| `reporterUid` | who told us |
| `targetType` | `post`, `comment` or `user` |
| `targetKey` | the post id, or `postId/commentId`, or the person's uid |
| `targetOwnerUid` | who posted the thing, or the person reported |
| `reason` | `spam`, `sexual`, `hate`, `violence` or `other` |
| `createdAt` | when it was sent |

The document's own id is `reporterUid__targetType__targetKey`, so the same
person reporting the same thing twice does not make a second row. Nothing in
the app can read, edit or delete a report — only this console can.

The reporter has already stopped seeing what they reported. The 24 hours is
about everyone else.

## Looking at what was reported

- **A post** — `posts/<targetKey>`. The `photos`, `taskName`, `caption` and
  `authorUid` are all on the document; each entry in `photos` carries the
  `storagePath` of its image.
- **A comment** — `posts/<postId>/comments/<commentId>`, which is exactly
  what `targetKey` reads with the slash in it.
- **A person** — `publicProfiles/<targetKey>` for their handle, and
  `posts` filtered by `authorUid == <targetKey>` for everything they have
  posted.

## Taking something down

Everything below is done in the console, not in the app.

1. **Remove a post** — open `posts/<id>` and use **Delete document**. It
   disappears from every feed and profile immediately. Its comments live
   under it and go with it. The images stay in Storage at the
   `storagePath` each `photos` entry names, and can be deleted there too.
2. **Remove a comment** — open `posts/<postId>/comments/<commentId>` and
   **Delete document**.
3. **Disable an account** — [Authentication → Users](https://console.firebase.google.com/project/sondr-cd439/authentication/users),
   find the uid, then the row menu → **Disable account**. They can no longer
   sign in or write anything. Their existing posts stay up until deleted, so
   delete those first if that is the point.
4. **Delete an account outright** — the same row menu → **Delete account**.
   This removes the sign-in only; their documents under `users/<uid>`,
   `publicProfiles/<uid>` and `posts` remain and have to be deleted by hand.

## Closing a report

Delete the report document once it has been dealt with, so the collection is
a queue rather than a log. If we ever want the history, copy it out first —
once deleted it is gone.

## What we promised

The App Store review notes and the support page both say we act on reports
within 24 hours. Two things have to stay true for that: someone looks at the
collection daily, and the support page keeps an address that reaches us.
