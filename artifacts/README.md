# Local task artifacts

This directory contains local media artifacts from Yoto jobs. Audio and icon
files are intentionally ignored by Git; the source repositories contain only
the downloader/MCP code and tests.

| Job | Audio | Icons | Yoto result |
| --- | --- | --- | --- |
| `toddler-bedtime-songs` | 18 tracks | 18 icons | Appended to `hKBXN` |
| `david-gibb-songbook` | 13 tracks | 13 icons | Appended to `ai1n1` |
| `pop-song-lullabies` | 34 tracks | 34 icons | Removed from `ai1n1` after correction |

Future jobs should keep a `manifest.json` beside `audio/` and `icons/` so an
interrupted operation can be resumed without re-downloading or re-uploading
completed tracks.

The `legacy-imagegen/` folder, if present, is historical input from the old
workflow only; new jobs must resolve existing Yoto user/public icons instead.
