---
name: youtube-to-yoto
description: Orchestrate a safe YouTube playlist to Yoto card import using the headless Downloader CLI and local yoto-local MCP server.
---

# YouTube → Yoto Playlist Studio

Use this skill for the complete workflow.

## User-facing flow

Ask for or infer only the missing inputs:

- YouTube video/playlist URL;
- target Yoto Card ID;
- audio format, default `m4a`;
- append-only confirmation.

Then:

1. Run `youtube-headless-downloader` into a new job directory.
2. Read the manifest and show playlist title, track count, order, and failures.
3. Read the target Yoto card and show an append preview.
4. Resolve existing Yoto user/public icons without ImageGen.
5. Start the MCP operation and expose its `operationId`.
6. Report progress and recover from interruptions through the manifest.
7. Read back the card and report before/after counts and any failed tracks.

## Example result

```text
Target: hKBXN
Current tracks: 18
New tracks: 34
Expected final count: 52
Mode: append-only
Operation: op_...
```

## Invariants

- Never upload or share credentials.
- Never use ImageGen for track icons.
- Never overwrite chapters without a user-requested replacement mode.
- Never report success without card readback.
- Keep audio, manifests, and logs under ignored `artifacts/<job-id>/` paths.
