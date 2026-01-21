# XcodeBuildMCP Setup Guide

This guide walks through setting up XcodeBuildMCP and connecting it to Cursor via MCP (Model Context Protocol) so that AI agents can directly interact with your Xcode projects, simulators, and build tools.

---

## Prerequisites

- macOS 14.5 or newer
- Xcode 16.x or newer (full app, not just command line tools)
- Node.js 18.x or newer
- Cursor IDE
- Homebrew (for installing dependencies)

---

## What You'll Accomplish

By the end of this guide:
- ✅ Node.js and npm installed
- ✅ Xcode developer path configured correctly
- ✅ XcodeBuildMCP server configured in Cursor
- ✅ AI agents can build, run, test, and interact with iOS simulators
- ✅ Full UI automation capabilities enabled

---

## Part 1: Install Prerequisites

### Step 1: Check System Requirements

```bash
sw_vers
xcodebuild -version
node --version
```

**Expected:**
- macOS 14.2 or later
- Xcode 15.4 or later
- Node.js v18 or later

### Step 2: Install Node.js (if needed)

Using Homebrew:

```bash
brew install node
```

Verify installation:

```bash
node --version
npm --version
```

You should see Node.js v18+ and npm v9+.

### Step 3: Fix Xcode Developer Path

If you see "tool 'xcodebuild' requires Xcode, but active developer directory is Command Line Tools", run:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

Verify:

```bash
xcodebuild -version
```

You should see your Xcode version (e.g., "Xcode 15.4").

---

## Part 2: Configure XcodeBuildMCP in Cursor

### Step 1: Check Existing MCP Configuration

Check if `~/.cursor/mcp.json` exists:

```bash
cat ~/.cursor/mcp.json
```

### Step 2: Add XcodeBuildMCP to Configuration

**If file doesn't exist**, create `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "npx",
      "args": [
        "-y",
        "xcodebuildmcp@latest"
      ]
    }
  }
}
```

**If file exists** (e.g., with Firebase), add XcodeBuildMCP:

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
    },
    "XcodeBuildMCP": {
      "command": "npx",
      "args": [
        "-y",
        "xcodebuildmcp@latest"
      ]
    }
  }
}
```

### Step 3: Restart Cursor

Completely quit Cursor (`Cmd + Q`) and reopen it. This loads the new MCP server.

---

## Part 3: Verify XcodeBuildMCP Connection

### Step 1: Test Basic Commands

In Cursor chat, ask the AI:

```
List all available iOS simulators
```

The AI should show you all installed simulators.

### Step 2: Discover Your Project

Ask the AI:

```
Discover Xcode projects in this workspace
```

It should find your `.xcodeproj` file.

### Step 3: List Schemes

Ask the AI:

```
What schemes are available in my Xcode project?
```

It should list your app schemes (e.g., "Prod1").

If all three work, you're fully set up! 🎉

---

## Part 4: Optional - Enable UI Automation (Beta)

For advanced features like screenshots, UI automation (tap/swipe), and video capture, you need additional dependencies.

### Install idb-companion (Facebook iOS Debug Bridge)

```bash
brew tap facebook/fb
brew install idb-companion
```

### Install fb-idb Client

```bash
pipx install fb-idb==1.1.7
```

**Note:** If you don't have `pipx`, install it first:

```bash
brew install pipx
pipx ensurepath
```

---

## What Can AI Agents Do Now?

With XcodeBuildMCP connected, AI agents can:

### Building & Running
- Build iOS apps for simulators or devices
- Build and run in one command
- Build for macOS targets
- Clean build artifacts

### Simulator Management
- List all available simulators
- Boot/shutdown simulators
- Open Simulator.app
- Erase simulator data
- Set simulator appearance (dark/light mode)
- Set GPS location
- Modify status bar

### App Testing
- Run unit tests
- Run UI tests
- Run tests on specific simulators
- Capture test logs

### App Installation & Launch
- Install apps on simulators
- Launch apps with bundle ID
- Stop running apps
- Get app bundle information

### UI Automation (with idb-companion)
- Take screenshots
- Get full UI hierarchy with coordinates
- Tap elements by coordinates or label
- Swipe gestures
- Type text
- Press hardware buttons
- Record simulator video

### Device Support (Physical Devices)
- List connected devices
- Build for physical devices
- Install apps on devices
- Run tests on devices
- Capture device logs

### Project Information
- Discover Xcode projects
- List available schemes
- Show build settings
- Get build paths

---

## Natural Language Commands Reference

XcodeBuildMCP allows you to use natural language to control Xcode. Here are common commands you can ask the AI:

### Building & Running

**Build for Simulator:**
- *"Build Prod1 for iPhone 15 Pro simulator"*
- *"Build Prod1 for iOS simulator"*

**Build & Run:**
- *"Build and run Prod1 on iPhone 15"*
- *"Build and run on iPhone 15 Pro"*
- *"Run the app on iPad Air simulator"*

**Clean Build:**
- *"Clean the Xcode build"*
- *"Clean build artifacts"*

### Testing

**Run Tests:**
- *"Run tests for Prod1"*
- *"Run all unit tests"*
- *"Run tests on iPhone 15 Pro Max simulator"*

**View Test Results:**
- *"Show me any test failures"*
- *"Show me the build errors"*

### Simulator Management

**List & Boot:**
- *"What simulators are available?"*
- *"List all iOS simulators"*
- *"Boot iPhone 15 Pro simulator"*
- *"Open the Simulator app"*

**Screenshots & UI:**
- *"Take a screenshot of the app"*
- *"Show me the UI hierarchy"*
- *"Describe the UI"*

**Simulator Settings:**
- *"Set simulator to dark mode"*
- *"Set GPS location to (latitude, longitude)"*
- *"Erase simulator data"*

### UI Automation

**Interact with UI:**
- *"Tap the button at coordinates (200, 400)"*
- *"Tap the login button"* (uses label)
- *"Type 'hello@example.com' in the text field"*
- *"Swipe from bottom to top"*

**Best Practice:** Always ask *"Describe the UI"* first to get exact element coordinates before tapping.

### Project Information

**Project Details:**
- *"Show build settings for Prod1"*
- *"What schemes are available?"*
- *"List all schemes"*
- *"Discover Xcode projects in this workspace"*

### Device Operations

**Physical Devices:**
- *"List connected devices"*
- *"Build for device"*
- *"Install app on device"*
- *"Launch app on device"*

---

## 💡 Pro Tips for Daily Use

1. **Always use natural language** - Don't worry about exact syntax, just describe what you want
2. **Specify simulator when needed** - Mention which iPhone/iPad for best results
3. **UI Automation requires coordinates** - Ask to "describe UI" first, don't guess from screenshots
4. **Build once, run many** - After building, you can quickly run on different simulators
5. **Use screenshots for debugging** - Visual confirmation is helpful
6. **Session defaults persist** - The AI remembers your project, scheme, and simulator between commands

---

## 📚 Example Workflows

Here are complete workflows for common tasks:

### Quick Test Run
```
1. "Build and run Prod1 on iPhone 15 Pro"
2. "Take a screenshot"
3. "Show me the build logs if there are errors"
```

### UI Testing Workflow
```
1. "Boot iPhone 15 simulator"
2. "Build and run the app"
3. "Describe the UI"
4. "Tap the login button at (x, y)"
5. "Type my credentials"
6. "Take a screenshot"
```

### Multi-Device Testing
```
1. "Run tests on iPhone 15 Pro"
2. "Run tests on iPad Air"
3. "Show me any test failures"
```

### Device Deployment
```
1. "List connected devices"
2. "Build for device"
3. "Install app on device"
4. "Launch app on device"
```

### Debug a Feature
```
1. "Build and run Prod1 on iPhone 15"
2. "Take a screenshot"
3. "Describe the UI"
4. "Tap element at (x, y)"
5. "Take another screenshot to verify"
```

---

## Troubleshooting

### "Node.js not installed" or version too old
- Install Node.js v18+ via Homebrew: `brew install node`
- Update Node.js: `brew upgrade node`

### "xcodebuild requires Xcode, but active developer directory is Command Line Tools"
- Fix Xcode path: `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`

### MCP Not Loading in Cursor
1. Check `~/.cursor/mcp.json` exists and is valid JSON
2. Restart Cursor completely (Cmd + Q, then reopen)
3. Check Cursor logs for MCP errors
4. Try explicit version: `"xcodebuildmcp@1.4.0"` instead of `@latest`

### Build Fails
- Clean build: Ask AI to "Clean the build"
- Check code signing in Xcode: Signing & Capabilities tab
- Verify scheme is correct: Ask AI to "List schemes"

### Simulator Not Found
- List available simulators: Ask AI
- Use exact simulator name from the list
- Boot simulator first if not running

### UI Automation Not Working
- Install idb-companion: `brew install idb-companion`
- Install fb-idb: `pipx install fb-idb==1.1.7`
- Restart Cursor after installing dependencies

### "Permission denied" or Sandbox Errors
- The AI may need to request additional permissions
- It will ask for `network`, `git_write`, or `all` permissions when needed
- Approve permission requests when prompted

---

## Advanced Configuration

### Using mise Instead of npx

If you prefer version management with `mise`:

```bash
brew install mise
```

Then update `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "mise",
      "args": [
        "x",
        "npm:xcodebuildmcp@1.4.0",
        "--",
        "xcodebuildmcp"
      ]
    }
  }
}
```

### Environment Variables

Add optional environment variables to your MCP config:

```json
{
  "mcpServers": {
    "XcodeBuildMCP": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp@latest"],
      "env": {
        "INCREMENTAL_BUILDS_ENABLED": "true",
        "XCODEBUILDMCP_SENTRY_DISABLED": "true"
      }
    }
  }
}
```

**Available variables:**
- `INCREMENTAL_BUILDS_ENABLED`: Enable experimental incremental builds
- `XCODEBUILDMCP_SENTRY_DISABLED`: Disable error reporting
- `XCODEBUILDMCP_DYNAMIC_TOOLS`: Load tools dynamically
- `XCODEBUILDMCP_ENABLED_WORKFLOWS`: Limit enabled workflows

---

## Security Notes

- XcodeBuildMCP has full access to build and run code on your machine
- Only use in trusted development environments
- Review what the AI is doing before confirming destructive operations
- Be cautious when running on physical devices
- Keep your MCP configuration secure

---

## Common Workflows

### Quick App Test
```
1. "Build and run Prod1 on iPhone 15 Pro"
2. "Take a screenshot"
3. "Show me any build errors"
```

### UI Testing Workflow
```
1. "Boot iPhone 15 simulator"
2. "Build and run the app"
3. "Describe the UI"
4. "Tap the login button at (x, y)"
5. "Type my credentials"
6. "Take a screenshot"
```

### Multi-Device Testing
```
1. "Run tests on iPhone 15 Pro"
2. "Run tests on iPad Air"
3. "Show me any test failures"
```

### Device Deployment
```
1. "List connected devices"
2. "Build for device"
3. "Install app on device"
4. "Launch app on device"
```

---

## Project Configuration

### Session Defaults

XcodeBuildMCP maintains session defaults for your project:

```json
{
  "projectPath": "/Users/kmaha/Dev/SONDR_V1/Prod1.xcodeproj",
  "scheme": "Prod1",
  "simulatorId": "UUID-OF-SIMULATOR",
  "useLatestOS": true
}
```

These are automatically configured when you first use the tools.

To change defaults, ask the AI:
```
"Update session defaults to use iPhone 15 Plus"
```

---

## Resources

- **XcodeBuildMCP GitHub:** https://github.com/cameroncooke/xcodebuildmcp
- **MCP Hub:** https://mcphub.com/mcp-servers/cameroncooke/xcodebuildmcp
- **Interactive Setup:** Run `/setup-xcodebuild-mcp` command in Cursor

---

**Last Updated:** January 2026  
**Maintained By:** SONDR Development Team
