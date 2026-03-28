# TIDAL Plugin for Squeezebox (HiRes Fork)

A plugin for [Logitech Media Server](https://github.com/LMS-Community/slimserver) (LMS/Squeezebox) that integrates TIDAL streaming with HiRes/DASH and Dolby Atmos support.

Forked from [michaelherger/lms-plugin-tidal](https://github.com/michaelherger/lms-plugin-tidal).

## Features

- Multi-account OAuth authentication
- HiRes FLAC streaming via DASH (up to 24-bit/192kHz)
- Dolby Atmos (EAC-3) playback via FFmpeg transcoding
- Custom OAuth client ID/secret support
- Library scanning with quality metadata (sample rate, bit depth, replay gain)
- Album quality tags: `[H]` High, `[M]` Max, `[A]` Atmos, `[E]` Explicit
- Material Skin UI integration

**Requires:** LMS >= 8.3.0, FFmpeg (for DASH and Atmos transcoding)

## What This Fork Changes

This fork includes significant code quality, security, and feature improvements over upstream.

### Security Fixes
- **Credential logging removed** — OAuth tokens and plaintext credentials no longer appear in logs
- **Custom credentials validated and masked** — API secret is masked in the settings UI
- **HTTPS for all image URLs** — no more mixed-content HTTP requests

### Bug Fixes
- **DASH temp file cleanup** — manifest temp files are cleaned up on object destruction
- **Bitrate calculation** — reports actual bitrate instead of misusing sample rate
- **Package-scoped mutation** — `$ct` in `_prepareTrack` and item titles in render functions are no longer mutated
- **Blocking scanner sleep removed** — `sleep(3)` in the library scanner replaced with non-blocking approach
- **`getMediaInfo` guard** — prevents crashes on missing dereference
- **Preference defaults** — all prefs have proper defaults, uses Perl truthiness consistently
- **Commented-out dead code removed** from ProtocolHandler

### Code Quality
- **Album filtering rewrite** — replaced monolithic `_filterAlbums` with a clean Group-Select-Filter pipeline
- **Media tag constants extracted** — no more magic strings for quality tags
- **Preference migration** — removed deprecated `enableDASHPreferHiRes` pref via migration
- **Simplified settings UI** — explicit content toggle is now a global checkbox
- **86-test test suite** covering core business logic (album filtering, quality tags, API helpers)
- **Hardened GitHub Actions** — release pipeline with SHA-1 verification and dry-run support

### New Features
- **LMS Favorites → TIDAL sync** — heart a track in Material Skin and it syncs to your TIDAL favorites

## Installation

### From Repository URL (recommended)

1. In LMS, go to **Settings > Plugins**
2. At the bottom, add this repository URL:
   ```
   https://raw.githubusercontent.com/27Bslash6/lms-plugin-tidal/main/repo/repo.xml
   ```
3. Install "TIDAL local (HiRes)" from the plugin list
4. Restart LMS

### Manual Installation

1. Download `TIDAL.zip` from the [latest release](https://github.com/27Bslash6/lms-plugin-tidal/releases)
2. Extract to your LMS plugin directory (e.g., `/var/lib/squeezeboxserver/Plugins/TIDAL/`)
3. Restart LMS

## Configuration

### Basic Setup

1. Go to **Settings > Plugins > TIDAL**
2. Click "Add Account" and complete the OAuth device flow
3. Select your preferred quality level

### HiRes (DASH) Setup

1. Enable **TIDAL DASH** in the experimental settings section
2. Copy the DASH transcode rules from `custom-convert.conf` into your LMS `custom-convert.conf`
3. Copy `custom-types.conf` into your LMS directory
4. Ensure FFmpeg is installed and accessible to LMS

### Dolby Atmos Setup

1. Enable **TIDAL Dolby Atmos** in the experimental settings
2. Atmos requires a client ID/secret that supports it (e.g., from an Android TV APK)
3. Enable **Custom Client ID / Secret** and enter your credentials
4. Copy the Atmos transcode rules from `custom-convert.conf` — you may need to adjust for your player setup

### Quality Tiers by Client ID

| Client ID/Secret | LOSSLESS (16/44.1) | HIRES LOSSLESS (24/192) | DOLBY ATMOS |
|---|---|---|---|
| Stock (built-in) | Yes | Yes (DASH required) | No |
| TIDAL Developer | Yes | Yes (DASH required) | No |
| Android TV APK | Yes (DASH required) | Yes (DASH required) | Yes |

## Transcoding

DASH and Atmos streams require FFmpeg transcoding. See `custom-convert.conf` for example transcode rules. The active rules are:

- **DASH (mpd -> flc):** Copies FLAC audio from the DASH manifest
- **Atmos passthrough (mp4eac3 -> mp4):** Direct passthrough for players that support EAC-3
- **Atmos bitstream (mp4eac3 -> flc):** Wraps EAC-3 in SPDIF framing, outputs as FLAC (works with squeezelite + AVR)

You may need to customize these for your player. Add MAC address restrictions in your `custom-convert.conf` to target specific players.

## Releasing

Releases are managed via GitHub Actions (`workflow_dispatch`).

### Steps

1. **Bump the version** in `install.xml`:
   ```xml
   <version>1.9.0</version>
   ```
2. **Commit and push** to `main`
3. **Go to GitHub Actions** > "Publish" workflow > "Run workflow"
4. **Enter the version** (must match `install.xml`) and click "Run workflow"
   - Use the dry_run option to test without publishing
5. The workflow will:
   - Zip the plugin files
   - Compute SHA-1 hash and update `repo/repo.xml`
   - Commit the updated `repo.xml` to `main`
   - Create a GitHub release with the zip attached
6. Users with the repo URL configured will see the update in LMS

### Version Scheme

- Upstream versions: `1.8.x`
- This fork: bump minor or patch as appropriate (e.g., `1.9.0`)

## Credits

- [Michael Herger](https://github.com/michaelherger) — original plugin author
- [philippe_44](https://github.com/philippe44) — original plugin co-author
- [smoothquark](https://github.com/smoothquark) — HiRes/DASH and Dolby Atmos implementation

## License

Same license as the upstream project.
