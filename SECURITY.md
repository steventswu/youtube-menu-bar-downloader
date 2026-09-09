# Security Policy

Please report security issues privately through GitHub's **Report a vulnerability** feature instead of opening a public issue. Do not include credentials, browser cookies, private media URLs, or downloaded files in a report.

The app intentionally does not read browser cookies or account credentials. YouTube URLs are passed to a bundled yt-dlp process as an argument without shell evaluation. Only official YouTube hosts and recognized video or playlist identifiers are accepted.
