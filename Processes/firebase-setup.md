# Firebase CLI & MCP Setup Guide

This guide walks through setting up Firebase CLI and connecting it to Cursor via MCP (Model Context Protocol) so that AI agents can directly interact with your Firebase project.

---

## Prerequisites

- Node.js & npm installed
- Cursor IDE
- Access to the Firebase project (Google account with permissions)

---

## What You'll Accomplish

By the end of this guide:
- ✅ Firebase CLI installed and authenticated
- ✅ Firebase MCP server configured in Cursor
- ✅ AI agents can read/write Firestore, manage Auth, deploy, and more
- ✅ Project initialized with `firebase.json` config

---

## Part 1: Install & Login to Firebase CLI

### Step 1: Check if Firebase CLI is already installed

```bash
firebase --version
```

If you see a version number (e.g., `15.3.1`), skip to Step 3.

### Step 2: Install Firebase CLI (if needed)

```bash
npm install -g firebase-tools
```

### Step 3: Login to Firebase

Run this in your terminal (not in Cursor):

```bash
firebase login --reauth
```

**What happens:**
1. Browser opens automatically
2. Select your Google account (mahajakelvin@gmail.com)
3. Grant Firebase CLI permissions
4. You'll see "Success! Logged in as [your-email]"

### Step 4: Verify Login

```bash
firebase projects:list
```

You should see all Firebase projects you have access to, including:
- **ProdApp** (prodapp-b90ac) - Our main project

---

## Part 2: Configure Firebase MCP in Cursor

### Step 1: Create MCP Configuration File

Create the file `~/.cursor/mcp.json` (in your home directory):

```json
{
  "mcpServers": {
    "firebase": {
      "command": "npx",
      "args": [
        "-y",
        "firebase-tools@latest",
        "mcp",
        "--dir",
        "/Users/kmaha/Dev/SONDR_V1"
      ]
    }
  }
}
```

**Important:** Update the `--dir` path if your project is in a different location.

### Step 2: Restart Cursor

Completely quit Cursor (`Cmd + Q`) and reopen it. This loads the new MCP server.

---

## Part 3: Initialize Firebase in Your Project

### Step 1: Configure Project

In the project root, update `.firebaserc`:

```json
{
  "projects": {
    "default": "prodapp-b90ac"
  },
  "targets": {},
  "etags": {}
}
```

### Step 2: Verify MCP Connection

In Cursor chat, ask the AI:

```
Can you check my Firebase environment?
```

The AI should be able to access your Firebase project and show details.

---

## Part 4: Test the Integration

### Quick Tests

Ask the AI to:
- "List all apps in my Firebase project"
- "Show me my Firestore collections"
- "What Firebase services am I using?"

If the AI can answer these, you're fully set up! 🎉

---

## What Can AI Agents Do Now?

With Firebase MCP connected, AI agents can:

### Data Operations
- Query Firestore collections (habits, tasks, posts, users)
- Add/update/delete documents
- View database structure

### Authentication
- List users
- Manage user accounts
- Configure auth settings

### Deployment
- Deploy Firestore security rules
- Update Firebase configuration
- Manage indexes

### Monitoring
- Check Crashlytics reports
- View analytics
- Inspect security rules

---

## Troubleshooting

### "Authentication Error: Your credentials are no longer valid"
Run: `firebase login --reauth`

### MCP Not Loading in Cursor
1. Check `~/.cursor/mcp.json` exists and is valid JSON
2. Restart Cursor completely
3. Check Cursor logs for MCP errors

### "PRECONDITION_FAILED: To proceed requires an active project"
1. Make sure `.firebaserc` has your project ID
2. Ask AI to run: `firebase_update_environment` with your project ID

---

## Quick Command Reference

```bash
# Check Firebase CLI version
firebase --version

# Login/reauth
firebase login --reauth

# List projects
firebase projects:list

# Check current project
firebase use

# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy everything
firebase deploy
```

---

## Security Notes

- MCP gives AI agents direct access to Firebase
- Only use in trusted environments
- Review what the AI is doing before confirming destructive operations
- Keep credentials secure

---

**Last Updated:** January 2026
**Maintained By:** SONDR Development Team
