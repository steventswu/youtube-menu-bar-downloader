# Contributing

Issues and pull requests are welcome. Keep user-facing text, documentation, commit messages, and new source comments in English.

Before opening a pull request, run:

```sh
swift test
sh scripts/build.sh
git diff --check
```

Changes to media conversion should also run `sh scripts/test-media.sh`. Do not commit downloaded media, `.app` bundles, bundled third-party binaries, credentials, browser cookies, or build output.
