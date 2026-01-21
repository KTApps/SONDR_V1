# Invite Friends Feature

## Overview

This document describes the "Invite your friends to SONDR" feature implemented in the app.

## Current Implementation

We implemented a simple text message sharing feature using SwiftUI's native `ShareLink` component. This opens the iOS Share Sheet, allowing users to share an invite message through various platforms including:

- iMessage
- WhatsApp
- Instagram
- Snapchat
- Email
- Copy link
- Any other sharing-enabled apps on the user's device

## Technical Details

**File:** `Prod1/Friends/AddFriends.swift`

**Component used:** `ShareLink` (available in iOS 16+)

**Code:**
```swift
ShareLink(item: "Join me on SONDR! Download the app and let's connect: https://apps.apple.com/app/sondr") {
    ZStack {
        Rectangle()
            .frame(width: 300, height: 40)
            .cornerRadius(10)
            .foregroundColor(.gray)
        Text("Invite your friends to SONDR")
            .font(AuthState.Typography.font_4_bold)
            .foregroundColor(.white)
    }
}
```

## Important: Placeholder Link

The current App Store URL is a **placeholder**:
```
https://apps.apple.com/app/sondr
```

**This link needs to be updated once the app is published on the App Store.** The correct format will be something like:
```
https://apps.apple.com/app/sondr/id123456789
```

You can find your app's App Store link in App Store Connect after publishing.

## Why Simple Text Message?

We considered several approaches:

1. **Simple text message** (current) - Quick to implement, works immediately
2. **Personalized referral links** - Would require storing referral codes in Firebase
3. **Dynamic links** - Firebase Dynamic Links was deprecated (shut down August 2025)

We chose the simple text message approach to get a working feature quickly. This can be enhanced later with:
- Referral tracking via Firestore
- Dynamic link providers like Branch.io, 1link.io, or Adjust (TrueLink)
- Personalized invite codes

## Future Enhancements

Potential improvements to consider:
- Add user's name to the invite message (e.g., "Join [username] on SONDR!")
- Implement referral code tracking in Firestore
- Add a dynamic link provider for deferred deep linking
- Track successful referrals and reward users
