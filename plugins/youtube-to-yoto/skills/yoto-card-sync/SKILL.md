---
name: yoto-card-sync
description: Safely append downloaded audio to Yoto cards through the local yoto-local MCP server, with resumable operations, card fingerprints, dry runs, and existing Yoto user/public icons.
---

# Yoto card sync

Use this skill after a headless download manifest exists and the user has
selected a target Yoto card.

## Required sequence

1. Read the target card and capture its ID, title, chapter count, first/last
   chapter, and fingerprint.
2. Resolve icons from Yoto's existing user icon catalog first, then Yoto's
   public icon catalog. Never use ImageGen, local icon PNGs, or custom icon
   upload for normal syncs.
3. Show an append preview with current count, new count, titles, and expected
   final count.
4. Require explicit confirmation before a write.
5. Start the resumable MCP operation and return its `operationId`.
6. Poll `yoto_get_operation` until completion, failure, or cancellation.
7. Read the card again and verify every appended track has a `yoto:#` audio
   reference and a `yoto:#` `icon16x16` reference.

## Safety rules

- Default mode is append-only; never replace existing chapters.
- Include `expectedChapterCount` and `expectedFingerprint` whenever available.
- If the card changes during upload, abort and request a new preview.
- For cleanup, identify the job and exact appended chapter list; never delete
  by an unverified guessed count.
- Keep OAuth in the local MCP token store. Never include tokens or Card IDs in
  a shared skill package.

## Recovery

Use the job manifest to skip tracks that already have matching video ID, audio
SHA-256, transcoded hash, and icon media ID. Retry only failed tracks. Do not
create duplicate chapters after a client timeout; inspect operation status and
the card before retrying.
