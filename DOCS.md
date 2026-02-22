# HyggeDash

A cozy smart home dashboard for iPad — control your Sonos speakers, HomeKit devices, and more from a single screen.

## Features

### 🎵 Music Control
- **Sonos Favorites** — Play anything saved in your Sonos Favorites (Spotify playlists, radio stations, etc.)
- **My Playlists** — Save Spotify, Apple Music, TIDAL, or Deezer links and play them directly on your Sonos speakers
- **Playback Controls** — Play, pause, skip, previous, and volume control
- **Speaker Groups** — View and manage Sonos speaker groups, create new groups, and switch between rooms
- **Share Extension** — Share links from Spotify or Apple Music directly into HyggeDash (iOS share sheet)

### 🏠 HomeKit
- **Scenes** — Trigger HomeKit scenes with one tap
- **Lights** — Control individual lights (on/off, brightness)
- **Switches** — Toggle smart switches and outlets

### ☀️ Weather
- Current conditions and temperature for your location

### 💬 Quotes
- Rotating inspirational quotes

### ⏰ Time
- Large clock display with date

## Setup

### Requirements
- iPad running iOS 17.0+
- Sonos speakers on the same Wi-Fi network
- Sonos account (for cloud API access)
- HomeKit-enabled devices (optional)

### Accounts

#### Sonos (Required)
1. Go to **Settings** → **Connect Sonos Account**
2. Sign in with your Sonos credentials
3. Your speakers, favorites, and groups will appear automatically

#### Spotify (Optional)
1. Go to **Settings** → **Connect Spotify Account**
2. Sign in with your Spotify credentials
3. Enables playing Spotify share links from your playlist library

> **Note:** Spotify account connection is optional. Sonos Favorites that contain Spotify content will play without a separate Spotify login.

### Adding Music

#### From the App
1. Tap the **+** button in the "My Playlists" section
2. Paste a Spotify, Apple Music, TIDAL, or Deezer link
3. The app auto-detects the service and content type
4. Give it a name and tap Save

#### From Spotify / Apple Music (Share Extension)
1. In Spotify or Apple Music, tap **Share** on any track, album, or playlist
2. Select **HyggeDash** from the share sheet
3. The link is saved automatically and appears in "My Playlists"

#### Sonos Favorites
Sonos Favorites are managed through the Sonos app. Any favorites you create there will appear automatically in HyggeDash.

## How Music Playback Works

HyggeDash uses two methods to play music:

### Sonos Favorites (Cloud API)
When you tap a Sonos Favorite, HyggeDash uses the Sonos Cloud API to start playback. This works from anywhere.

### Music Service Links (Local Network / UPnP) 🏠
When you tap a Spotify/Apple Music/TIDAL link from "My Playlists", HyggeDash sends commands **directly to your Sonos speakers** over your local Wi-Fi network using UPnP — the same protocol the Sonos desktop app uses.

> **⚠️ Local network required:** Music service links (marked with a 🏠 icon) only work when your iPad is on the **same Wi-Fi network** as your Sonos speakers.

This approach:
- Clears the current queue
- Adds the music service content with the correct metadata
- Starts playback immediately
- Supports Spotify, Apple Music, TIDAL, and Deezer

### Speaker Groups
- Tap the room name (top-right of the Music card) to switch rooms
- Tap the **currently selected** room to edit its speaker group
- Use the grouping screen to add/remove speakers from a group

## Architecture

```
┌─────────────────────────────────────────────┐
│                  HyggeDash                  │
├──────────┬──────────┬───────────┬───────────┤
│   Time   │  Quotes  │   Music   │   Home    │
│          │          │           │           │
│  Clock   │ Rotating │ Now       │ Scenes    │
│  Weather │ quotes   │ Playing   │ Lights    │
│          │          │ Controls  │ Switches  │
│          │          │ Library   │           │
└──────────┴──────────┴───────────┴───────────┘
                          │
              ┌───────────┼───────────┐
              │           │           │
         Sonos Cloud   Local UPnP   Spotify
         API (REST)    (SOAP/HTTP)   Web API
              │           │           │
         Favorites    Share Links   Auth/Skip
         Groups       Queue Mgmt   (optional)
         Playback
         Volume
```

## Troubleshooting

### "No speakers found"
- Make sure your Sonos account is connected (Settings → Connect Sonos Account)
- Verify your Sonos speakers are powered on and connected to Wi-Fi

### Music service links don't play
- Ensure your iPad is on the **same Wi-Fi network** as your Sonos speakers
- The 🏠 icon indicates local network is required
- Check that "Local Network" permission is enabled for HyggeDash in iOS Settings

### Skip doesn't work on Spotify content
- Some Spotify radio stations have skip limits imposed by Spotify
- If you've connected your Spotify account, skip commands route through the Spotify API which may avoid this

### Sonos Favorites not showing
- Favorites are synced from your Sonos account — add them via the Sonos app
- Pull down to refresh, or switch to another tab and back

## Privacy

- **Sonos credentials** are stored in the iOS Keychain (encrypted on-device)
- **Spotify credentials** are stored in the iOS Keychain (uses PKCE — no client secret stored)
- **Music links** are stored locally on-device (in App Group shared storage)
- **No analytics or tracking** — HyggeDash does not collect any usage data
- **Local network access** is used only to communicate with Sonos speakers on your Wi-Fi
