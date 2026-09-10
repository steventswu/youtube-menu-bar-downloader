---
name: youtube-headless-downloader
description: Download public YouTube videos or playlists through the bundled Downloader.app headless CLI, with JSONL progress, ordered audio files, retries, and a per-job manifest.
---

# YouTube headless downloader

Use this skill when a workflow needs local audio from a public YouTube video or
playlist without opening the menu-bar UI.

## Contract

Run the existing packaged app, never a second ad-hoc yt-dlp installation:

```sh
Downloader.app/Contents/MacOS/Downloader \
  --headless \
  --url "$YOUTUBE_URL" \
  --output "$JOB_DIR" \
  --audio-format m4a
```

Supported options are `--audio-format m4a|mp3|opus`, `--no-playlist`,
`--manifest`, `--tools`, and `--max-retries 0...10`.

The command emits JSONL events such as `job_started`, `playlist_loaded`,
`track_started`, `track_progress`, `track_retry`, `track_completed`,
`track_failed`, and `job_completed`. The manifest is the source of truth for
resume and retry decisions.

## Safety and behavior

- Download only public content the user is authorized to save.
- Preserve playlist order and four-digit prefixes.
- Treat a non-zero exit code or a failed manifest track as actionable; do not
  claim the entire playlist succeeded.
- Keep the job directory outside source code, normally under
  `artifacts/<job-id>/`.
- Never place YouTube cookies, OAuth tokens, or personal paths in the plugin.

## Handoff to Yoto

Pass the manifest's ordered track records to `yoto-card-sync`. Do not manually
retype titles or reorder files. The Yoto workflow should use each track's
video ID, audio path, title, and SHA-256.
