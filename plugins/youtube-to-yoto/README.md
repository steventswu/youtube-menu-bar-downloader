# YouTube → Yoto Playlist Studio

This plugin turns a public YouTube playlist into an append-only Yoto workflow:

1. Download audio with the packaged Downloader headless CLI.
2. Save ordered files, SHA-256 values, failures, and resume data in a job manifest.
3. Preview the target Yoto card before changing it.
4. Resolve existing Yoto user icons first, then Yoto public icons.
5. Append tracks through the local `yoto-local` MCP server.
6. Read the card back and verify every audio/icon reference.

The plugin never uses ImageGen for track icons and never includes OAuth tokens,
Card IDs, user icon IDs, audio files, or local personal paths.

## What is included

| Component | Purpose |
| --- | --- |
| `skills/youtube-headless-downloader` | Download one video or a playlist with JSONL progress and a manifest. |
| `skills/yoto-card-sync` | Append audio to Yoto cards with fingerprints, progress, resume, and existing Yoto icons. |
| `skills/youtube-to-yoto` | Conversational wizard that coordinates the whole workflow. |
| `assets/job-manifest.schema.json` | Schema for resumable job records. |
| `scripts/check-prerequisites.sh` | Read-only local installation check. |

## Prerequisites

- macOS 13 or newer on Apple Silicon.
- A built or released `Downloader.app`.
- Node.js 20 or newer.
- A Yoto account and a Yoto Developer Public Client.
- The local `YotoMCP` server built from the companion repository.
- A public YouTube video or playlist that you are authorized to download.

The plugin is intentionally an orchestration layer. It does not bundle the
Downloader binary, FFmpeg, Deno, Yoto OAuth tokens, or a Yoto account.

## 1. Get the repositories

```sh
git clone https://github.com/steventswu/youtube-menu-bar-downloader.git downloader
git clone https://github.com/steventswu/yoto-mcp-local.git yoto-mcp-local
cd downloader

cd ../yoto-mcp-local
npm ci
npm run build
cd ../downloader
```

Install the released Downloader app, or build it locally:

```sh
python3 scripts/package.py
```

Run the prerequisite check from the plugin directory:

```sh
plugins/youtube-to-yoto/scripts/check-prerequisites.sh
```

If the app or YotoMCP lives elsewhere, set these variables for the check:

```sh
YOUTUBE_YOTO_WORKSPACE="$PWD" \
DOWNLOADER_APP="/Applications/Downloader.app" \
YOTO_MCP_DIR="../yoto-mcp-local" \
plugins/youtube-to-yoto/scripts/check-prerequisites.sh
```

## 2. Configure the local Yoto MCP server

Add a local `yoto-local` server entry to your Codex configuration. Use your
own Public Client ID; it is not a client secret. Do not put refresh tokens in
this file.

```toml
[mcp_servers.yoto-local]
command = "/absolute/path/to/node"
args = ["/absolute/path/to/yoto-mcp-local/dist/index.js"]
cwd = "/absolute/path/to/yoto-mcp-local"
default_tools_approval_mode = "writes"

[mcp_servers.yoto-local.env]
YOTO_CLIENT_ID = "your-public-client-id"
YOTO_ENABLE_WRITES = "true"
YOTO_AUDIO_ROOT = "/absolute/path/to/artifacts"
YOTO_MANIFEST_ROOT = "/absolute/path/to/artifacts/manifests"
```

The first write operation will require Yoto OAuth consent. The token is stored
locally by YotoMCP with restricted permissions; it is not part of this plugin.

## 3. Install or load the plugin

Use the `plugins/youtube-to-yoto` directory as the plugin source in your Codex
plugin workflow. For a simple local setup, the three `SKILL.md` directories can
also be copied into your Codex skills directory.

When publishing through the OpenAI Skills API, upload this plugin's skill
bundle as a directory or ZIP and create a versioned release. Keep the local
YotoMCP server and Downloader release as separate dependencies.

## 4. Use the conversational wizard

In Codex, ask:

```text
Import this YouTube playlist into Yoto Card hKBXN:
https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID
```

The wizard should show a preview similar to:

```text
Target card: hKBXN
Current chapters: 18
New tracks: 34
Expected result: 52 chapters
Mode: append only
```

It will ask for confirmation before the card write. During the operation it
returns an `operationId`; use the operation status tool to monitor progress.

## 5. Use the Downloader headless CLI directly

```sh
JOB_DIR="$PWD/artifacts/pop-song-lullabies"

dist/Downloader.app/Contents/MacOS/Downloader \
  --headless \
  --url 'https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID' \
  --output "$JOB_DIR" \
  --audio-format m4a \
  --max-retries 2 \
  > "$JOB_DIR/events.jsonl"
```

The command writes ordered `.m4a` files and `manifest.json`. JSONL events
include `job_started`, `playlist_loaded`, `track_progress`,
`track_completed`, `track_failed`, `track_retry`, and `job_completed`.

Exit codes:

- `0`: all tracks completed;
- `1`: fatal setup or input error;
- `2`: playlist completed with one or more failed tracks.

Do not continue to Yoto upload until the manifest has been checked. Failed
tracks can be retried without re-downloading successful tracks.

## 6. Recovery and correction

If a process stops midway:

1. Read the job manifest.
2. Inspect the operation status by `operationId` if the MCP process is still running.
3. Resume only tracks that are not `attached`.
4. Re-run the append preview with the saved card fingerprint.

If the wrong card was selected, use the job ID and expected fingerprint to
remove only that job's appended chapters. Never truncate a card by a guessed
chapter count.

## Icon behavior

Icons are resolved from existing Yoto catalogs:

1. the authenticated user's custom icons;
2. Yoto public icons;
3. a fixed music-note/baby fallback.

No PNG is generated or uploaded by the normal workflow. No icon media IDs are
bundled in this repository.

## Troubleshooting

### `Downloader.app` is missing

Install the latest Apple Silicon release or run `python3 scripts/package.py`.

### Yoto tools are read-only

Check `YOTO_ENABLE_WRITES=true`, rebuild `YotoMCP`, and complete OAuth again so
the token has content and icon-management scopes.

### A track fails with a YouTube format error

Keep the failed manifest record, retry later, or use another audio format. Do
not mark the whole job successful when any track remains failed.

### The card fingerprint changed

Someone or another operation changed the card. Read it again, review a new
append preview, and only then restart the job.

## Privacy and security

Never commit or share:

- OAuth tokens or secrets;
- `Card ID` values from your account;
- user icon media IDs;
- local absolute paths;
- downloaded audio;
- job manifests containing personal card/source history.

Download only content you are authorized to save, and review the applicable
YouTube and Yoto terms before using the workflow.
