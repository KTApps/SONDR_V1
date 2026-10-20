#!/usr/bin/env python3
"""Give every existing comment the audience of the post it is on.

Comments written before `audience` existed have no such field, and the new
read rule requires the reader to be in it — so without this they vanish for
everybody, their own author included. One-off; safe to re-run (a comment
that already has an audience is left alone).

Runs as the project owner, through the Firebase CLI's own cached
credential, so it bypasses security rules. Reads and prints document PATHS
and AUDIENCES only — never comment text.

    python3 tools/backfill_comment_audience.py            # dry run
    python3 tools/backfill_comment_audience.py --apply
"""

import json
import os
import re
import shutil
import sys
import urllib.parse
import urllib.request

PROJECT = "sondr-cd439"
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"


def oauth_client():
    """The OAuth client the Firebase CLI's cached refresh token belongs to.

    Read out of the installed CLI rather than copied in here. The pair is
    public — it ships in every firebase-tools install and in the published
    npm tarball — but a literal Google client secret in a repo trips secret
    scanners, and the CLI is the honest source anyway. Same env overrides
    the CLI itself honours.
    """
    cid, secret = os.environ.get("FIREBASE_CLIENT_ID"), os.environ.get(
        "FIREBASE_CLIENT_SECRET"
    )
    if cid and secret:
        return cid, secret
    which = shutil.which("firebase")
    if not which:
        sys.exit("firebase CLI not on PATH; set FIREBASE_CLIENT_ID/_SECRET instead")
    # `firebase` resolves to <pkg>/lib/bin/firebase.js, so walk up to the
    # package root and read <pkg>/lib/api.js from there.
    here = os.path.dirname(os.path.realpath(which))
    for _ in range(5):
        api = os.path.join(here, "lib", "api.js")
        if os.path.exists(os.path.join(here, "package.json")) and os.path.exists(api):
            break
        here = os.path.dirname(here)
    else:
        sys.exit("could not find firebase-tools; set FIREBASE_CLIENT_ID/_SECRET instead")
    try:
        src = open(api).read()
    except OSError:
        sys.exit(f"cannot read {api}; set FIREBASE_CLIENT_ID/_SECRET instead")
    found = {
        name: re.search(rf'envOverride\("FIREBASE_{name}", "([^"]+)"\)', src)
        for name in ("CLIENT_ID", "CLIENT_SECRET")
    }
    if not all(found.values()):
        sys.exit("could not find the OAuth client in the installed firebase-tools")
    return found["CLIENT_ID"].group(1), found["CLIENT_SECRET"].group(1)


def _request(url, *, token=None, body=None, method=None, form=False):
    if form:
        data, headers = urllib.parse.urlencode(body).encode(), {
            "Content-Type": "application/x-www-form-urlencoded"
        }
    elif body is not None:
        data, headers = json.dumps(body).encode(), {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        }
    else:
        data, headers = None, {"Authorization": f"Bearer {token}"}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    return json.loads(urllib.request.urlopen(req).read().decode())


def access_token():
    path = os.path.expanduser("~/.config/configstore/firebase-tools.json")
    refresh = json.load(open(path))["tokens"]["refresh_token"]
    client_id, client_secret = oauth_client()
    return _request(
        "https://oauth2.googleapis.com/token",
        body={
            "client_id": client_id,
            "client_secret": client_secret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        },
        form=True,
    )["access_token"]


def strings(field):
    return [v["stringValue"] for v in field.get("arrayValue", {}).get("values", [])]


def main():
    apply = "--apply" in sys.argv
    token = access_token()

    posts = {}
    for row in _request(
        BASE + ":runQuery",
        token=token,
        body={
            "structuredQuery": {
                "from": [{"collectionId": "posts"}],
                "select": {"fields": [{"fieldPath": "audience"}]},
            }
        },
    ):
        doc = row.get("document")
        if doc:
            posts[doc["name"].rsplit("/", 1)[1]] = strings(
                doc.get("fields", {}).get("audience", {})
            )

    comments = []
    for row in _request(
        BASE + ":runQuery",
        token=token,
        body={
            "structuredQuery": {
                "from": [{"collectionId": "comments", "allDescendants": True}],
                "select": {"fields": [{"fieldPath": "audience"}]},
            }
        },
    ):
        doc = row.get("document")
        if doc:
            comments.append((doc["name"], "audience" in doc.get("fields", {})))

    print(f"{len(posts)} posts, {len(comments)} comments\n")
    todo = []
    for name, has_audience in comments:
        short = name.split("/documents/")[1]
        post_id = short.split("/")[1]
        audience = posts.get(post_id)
        if has_audience:
            print(f"  SKIP  {short}  (already has an audience)")
        elif audience is None:
            print(f"  ORPHAN {short}  (no such post — left alone)")
        else:
            print(f"  SET   {short}  -> {audience}")
            todo.append((name, audience))

    print(f"\n{len(todo)} to write.")
    if not apply:
        print("Dry run. Re-run with --apply to write.")
        return
    for name, audience in todo:
        _request(
            f"https://firestore.googleapis.com/v1/{name}"
            "?updateMask.fieldPaths=audience",
            token=token,
            method="PATCH",
            body={
                "fields": {
                    "audience": {
                        "arrayValue": {
                            "values": [{"stringValue": u} for u in audience]
                        }
                    }
                }
            },
        )
        print(f"  wrote {name.split('/documents/')[1]}")
    print("Done.")


if __name__ == "__main__":
    main()
