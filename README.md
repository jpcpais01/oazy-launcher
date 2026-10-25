# Oazy Launcher

A fast, good-looking launcher for the games and apps on a Windows PC, built with Godot 4.

- Console-style Home with a tile carousel, full-screen artwork and an accent colour taken from each game.
- Finds Steam, Epic Games and GOG installs automatically and pulls covers, heroes and logos from Steam.
- Library grid with instant search, filters and sorting. Playtime tracking for games launched from Oazy.
- Updates itself from GitHub Releases with a what's-new screen and a live download screen.
- Everything is drawn with a handful of cheap canvas shaders on the Compatibility renderer, so it starts instantly and idles lightly (it drops to 30 fps when unfocused, 12 fps while a game runs).

## Download

Grab `OazyLauncher.exe` from the [latest release](https://github.com/jpcpais01/oazy-launcher/releases/latest). It is a single, portable exe. Your library and settings live in `%APPDATA%\OazyLauncher`.

The exe is signed with a self-signed certificate until a real code-signing certificate is configured, so Windows SmartScreen may ask for confirmation on first run ("More info" → "Run anyway").

## How releases work

Every merge to `main` runs `.github/workflows/build.yml`:

1. Imports the project and runs the headless smoke test (`-- --smoke-test`).
2. Exports one Windows exe with the PCK embedded (no zip, no extra files) and stamps the version `VERSION.<commit count>`.
3. Signs it with `osslsigncode`: the `WINDOWS_CERT_PFX` (base64) and `WINDOWS_CERT_PASSWORD` secrets if they exist, otherwise a self-signed certificate made for that build.
4. Runs the packaged exe headless on a Windows runner as a second smoke test.
5. Publishes a GitHub release `v<version>` whose notes are the `patch-notes/*.md` files added since the previous release.

Each change adds a player-facing entry in [`patch-notes/`](patch-notes/README.md).

## Development

Open the folder in Godot 4.5+. Useful flags: `-- --smoke-test` runs the self-test and exits with its result. `tools/make_icon.py` regenerates the app icon.

Keyboard: arrows/Enter on Home, Tab to switch pages, Ctrl+F search, Ctrl+N add, F favourite, Delete remove, F11 fullscreen. Controllers work too (D-pad, A, B, shoulders).
