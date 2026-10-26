class_name ShortcutsSheet
## The keyboard shortcuts card (F1, or "keyboard shortcuts" in search).

const MARKDOWN := "### Anywhere
- **Ctrl + Alt + O** opens Start from any app.
- **Ctrl + Alt + D** shows your desktop: every window steps aside. Press it again to bring them back.

### On the desktop
- **Just type** to search apps, games, settings, sums and the web.
- **Ctrl + F** opens Start search.
- **Ctrl + Space** opens Claude, like clicking the orb.
- **Ctrl + L** opens your Library, **Ctrl + ,** opens Settings.
- **Ctrl + N** adds a game or app. You can also drop an .exe or shortcut onto Oazy.
- **F11** or **Alt + Enter** switches between fullscreen and a window.
- **F1** shows this card.

### In Start search
- **↑ ↓** pick a result, **Enter** opens it, **Esc** closes Start.
- Type a sum like `19.99*3` and press **Enter** to copy the answer.

### Claude (the orb)
- **Enter** sends, **Shift + Enter** starts a new line, **Esc** closes it.
- **Right-click** the orb (or click the search bar) for Start.

### Oazy's windows
- **Ctrl + W** closes the active window, **Esc** minimises it.
- Drag a window to the top edge to maximise, or to a side to snap.

### Taskbar
- **Scroll** over the sound icon to change the volume, **middle-click** it to mute. Click it for quick settings.
- **Middle-click** an app to open another window of it. Click the clock for a calendar, or the weather for the forecast.

### Controller
- **Start** or **Guide** opens Start, **B** closes it."


static func dialog() -> NotesDialog:
	var d := NotesDialog.new()
	d.title = "Keyboard shortcuts"
	d.subtitle = "Get around Oazy without reaching for the mouse."
	d.markdown = MARKDOWN
	return d
