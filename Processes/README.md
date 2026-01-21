# SONDR Processes Documentation

This folder contains standardized processes and setup guides for the SONDR project.

---

## Purpose

This folder holds **repeatable processes and procedures** that team members need to follow for various development tasks and setup requirements.

---

## Available Guides

### 🔥 [firebase-setup.md](./firebase-setup.md)
Complete guide for setting up Firebase CLI and MCP integration with Cursor IDE.

**What it covers:**
- Installing Firebase CLI
- Authenticating with Firebase
- Configuring MCP (Model Context Protocol) in Cursor
- Enabling AI agents to interact with Firebase directly

**Slash command:** `/setup-firebase` - Quick interactive setup via AI assistant

### 📱 [xcodebuild-mcp-setup.md](./xcodebuild-mcp-setup.md)
Complete guide for setting up XcodeBuildMCP to control Xcode, simulators, and iOS builds through AI agents in Cursor.

**What it covers:**
- Installing Node.js and prerequisites
- Configuring Xcode developer path
- Setting up XcodeBuildMCP in Cursor
- Building, running, and testing iOS apps via AI
- UI automation and simulator control

**Slash command:** `/setup-xcodebuild-mcp` - Quick interactive setup via AI assistant

---

## How to Use These Guides

### Option 1: Read the Documentation
Open any guide in this folder and follow the step-by-step instructions.

### Option 2: Use Slash Commands (Recommended)
In Cursor chat, type `/` and select the relevant command:
- `/setup-firebase` - Interactive Firebase setup with AI guidance
- `/setup-xcodebuild-mcp` - Interactive XcodeBuildMCP setup with AI guidance

The AI assistant will guide you through each step interactively.

---

## Adding New Processes

When documenting new repeatable processes:

1. **Add detailed documentation** to this `Processes/` folder
2. **Create a slash command** in `.cursor/commands/` for interactive execution
3. **Update this README** with links to your new process guide
4. **Test the process** thoroughly to ensure accuracy

---

## Project Context

- **Project:** SONDR_V1 (iOS Habit Tracking App)
- **Tech Stack:** SwiftUI, Firebase
- **Firebase Project:** ProdApp (prodapp-b90ac)
- **Xcode Project:** Prod1.xcodeproj
- **Development Tools:** Cursor IDE with Firebase MCP & XcodeBuildMCP
- **Development Branch:** Development
- **Repository:** /Users/kmaha/Dev/SONDR_V1

---

## Need Help?

If you encounter issues with any process:
1. Check the troubleshooting section in the relevant guide
2. Ask the team or project lead
3. Update the guide if you discover new solutions

---

**Last Updated:** January 2026
