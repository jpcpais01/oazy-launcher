# Oazy Launcher

A personal desktop shell for a Windows PC, built with Godot 4: one calm, glassy place to open apps, games, folders and the web, and to switch between everything that's running.

- **Desktop** with the time, a "continue playing" card, recently played games and a small system glance, over a procedural oasis wallpaper that follows the time of day.
- **Taskbar** with pinned apps and every open Windows window grouped by app, live DWM previews on hover, click to focus or minimise.
- **Start** with pinned apps, all installed apps (the Windows AppsFolder), recent games, places, power options and search across apps, games and the web.
- **Glass windows** for Oazy's own apps (Library, Settings): drag, resize, snap, maximise, minimise, several at once.
- **Library** that finds Steam, Epic Games and GOG installs, pulls covers, heroes and logos from Steam, and tracks playtime.
- **Ctrl + Alt + O** brings Oazy to the front from any app.
- Updates itself from GitHub Releases with a what's-new screen and a live download screen.
- Drawn with a few cheap canvas shaders (liquid glass, wallpaper) on the Compatibility renderer.

### How Oazy talks to Windows

`native/oazy_host.cs` is a small C# 5 helper that Oazy compiles on first run with the .NET Framework compiler that ships with Windows (`csc.exe`) and caches in the data folder. Oazy talks to it over a pipe: it lists and watches top-level windows, focuses, minimises and closes them, places live window thumbnails, renders app icons, enumerates installed apps and reports CPU and memory. If it can't start, Oazy keeps working with its own windows only.

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

Keyboard: type on the desktop to search, Ctrl+F Start search, Ctrl+L Library, Ctrl+, Settings, Ctrl+N add, Ctrl+W close window, Esc minimise window, F11 fullscreen. A controller's Start/Guide button opens Start.

`-- --screenshots=<dir>` renders the main screens to PNGs with sample data and mock windows (CI uploads these).
