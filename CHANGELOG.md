# Changelog

## v2.0.1

A security, privacy and reliability update. Nothing changes in how the shortcuts work, and your existing shortcuts and settings are kept.

### Privacy
- **Three new tray menu options** for anyone who types private information (patient details, for example):
  - **Type expansions directly (no clipboard)** types every expansion key by key, so clipboard history (Win+V), cloud clipboard and clipboard managers never see it.
  - **Hide expansion text in lists** shows only shortcut names in the Quick Expansion Picker (Alt+Q) and the editor, which helps when you share your screen. Double-click a shortcut to see or edit its text.
  - **Alt+C capture (uses the clipboard)** can be unticked to turn Alt+C off. Alt+C has to use the other app's normal Copy, so Windows may keep a copy of the selection. The first time you use it (or every time, with "Type expansions directly" on), Alt+C warns you about that before capturing.
  - Recommended for clinical use: the first two on, Alt+C off.
- Notices after saving, renaming or deleting show only the shortcut's name, never its text.
- Your old clipboard is put back after a paste or a capture only if nothing else has changed the clipboard in the meantime, so something you copied is never overwritten.

### Security
- **Importing a CSV file:** shortcuts that press keys, switch windows or pause (`{key:}`, `{focus:}`, `{wait:}`) are no longer imported automatically. You see each one in a review window that shows every action and the complete text, and decide one by one. **Skip** is the default. Shortcuts that only type text are imported as before.
- CSV import reads Excel-style files, including quoted text with line breaks. A file with a quote that is never closed is refused entirely, instead of being read wrongly.
- `{wait:}` pauses are capped at 30 seconds.
- A `.lnk` shortcut whose destination Windows can't read is refused, since what it opens can't be checked.

### Reliability
- Every change to your shortcut files (adding, editing, deleting, importing, start-up updates) is now saved the same safe way: a temporary file is written and swapped in with one Windows call. A failed save leaves the file exactly as it was. The window you were typing in stays open so nothing is lost, and you're told if an automatic backup didn't work.
- Changing the trigger keys is all-or-nothing. If any shortcut can't move to the new key because the name is taken, nothing is changed and you see which ones are in the way.
- Renaming a shortcut in the editor to a name another shortcut already uses is refused, instead of silently replacing it. The `$$` instant-fire marker is kept on rename.
- The undo history and usage statistics, and CSV and statistics exports, are saved the same safe way, so an existing file is never lost.
- **Backup Now (Alt+B)** says which file failed, if one does.

### Fixes
- Highlight text and hold `;` + C: a long hold no longer types a stray `;` afterwards, which replaced the highlighted text.
- A fast `;` followed by a letter that is a `;` shortcut (`;c`, `;v`, `;a` and the rest) now runs the shortcut without typing the `;` first.

## v2.0.0

### New
- **Hold keys: Ctrl and Alt, now on your home row.** Tray menu → **Hold ; for Ctrl, hold ` for Alt**. On from the start: new installs see it in the welcome message, and upgrades get a one-time "What's New" message. Untick it in the tray menu to turn it off. A quick tap of `;` or `` ` `` types it as usual; holding it and pressing another key gives Ctrl or Alt + that key. Hold `;` + C copies even part of a text you're editing, which typed shortcuts can't. Holding Caps Lock works as Alt too (see the next item). **Hold Keys Timing…** sets how long a hold takes (default 200 ms).
- **Caps Lock is a launcher key, built in.** Tap Caps Lock = backtick (Caps Lock then C opens Claude); hold Caps Lock + a key = Alt; Shift + Caps Lock = normal Caps Lock. On from the start; no SharpKeys or registry change needed (SharpKeys still works if you prefer it). Untick **Caps Lock: tap = `, hold = Alt** in the tray menu to restore normal Caps Lock.
- **Middle mouse button.** Works like the semicolon by default. Tray menu → **Middle mouse button** to pick: **Click = `, hold = Alt** (like Caps Lock: click then a letter opens a launcher), **Click = ;, hold = Ctrl** (like the semicolon: click then V pastes; highlight with the mouse, hold the wheel, tap C to copy; hold and scroll to zoom), or **Off**. The new default replaces the plain middle click: hold **Shift** while clicking for the normal middle click, or choose **Off**. Upgrades get a one-time "What's New" message about it.
- **Starter mode.** New installs start with just the built-in `;`, `` ` `` and `=` shortcuts. Choose **Unlock Full Features** from the tray menu for custom shortcuts, the editor and everything else.
- **Clipboard privacy.** Expanded text is kept out of Windows clipboard history (Win+V) and cloud clipboard sync.

### Changed
- **New `;` layout for new installs.** `;e` is line end and `;l` is line start, as in earlier versions. The emoji picker moves to `;8` (Shift+8 is `*`, like long-pressing `*` in SpeedKee). Lock PC moves to `;L`, so it's harder to hit by accident. `;E` stays as line end. New `;A` selects all and copies in one step, which works in a text box where typing `;c` would replace the selection. Existing shortcuts are never changed. Built-in shortcuts you don't have yet, such as `;8` and `;A`, are added automatically the next time the script starts.

### Removed
- **F-Key Hub** (F-key tap, long-press, double-tap and combo actions, plus the F-Key Manager). F1–F12 now always behave normally. Leftover `megabar.ini` files and the `[FKeys]` section in `prefs.ini` are ignored and can be deleted.

### Security
- Launchers now use an allowlist of file types (programs, shortcuts, common documents, media and folders). Scripts, installers and similar files are blocked.
- Launchers are checked every time they run, not just when added, so an entry written into `launchers.ahk` by another program is still checked.
- `.lnk` shortcuts are checked against what they actually open.
- Powerful system tools (cmd, PowerShell, regedit and others) ask for confirmation before running.

### Fixes
- A launcher pointing to a `.lnk` file that Windows can't read (deleted, or a special Start menu shortcut) no longer crashes with "This local variable has not been assigned a value".
- Built-in shortcuts are no longer added on top of a launcher with the same trigger. Upgrading from v1.0.0 could leave, for example, an old `;c` Calculator launcher and the new `;c` Copy fighting over one trigger. If you already have duplicates, delete the one you don't want with **Alt+E**.
- The editor's Type column now labels program and `.lnk` launchers as **App**. It used to show every one of them as "Document".
- Launchers for programs in folders with spaces or brackets, such as `C:\Program Files (x86)\...`, can now be added and work correctly.
- Saving a shortcut no longer triggers a full reload of the script a few seconds later.
- Editing a multi-line expansion in the editor no longer turns its line breaks into ` <- `.
- `{cursor}` now places the caret in the right spot (it was one character off).
- Keystroke sequences no longer insert stray spaces between text and keys.
- Undo no longer deletes unrelated text after keystroke sequences or `{cursor}` expansions; it explains that these can't be undone instead.
- CSV import handles quoted fields correctly, and shortcuts like `-=` survive an export and re-import.
- Choosing "Overwrite it everywhere" now really removes the old copy.
- The `$$` instant-fire marker is kept when expansions are edited or deleted.
- A lock file left behind by a crash no longer blocks saving or auto-reload.
- Help screens now show your own `` ` `` launchers and what your date shortcuts produce today, instead of a fixed list that could be wrong.
- Removed a leftover pop-up shown every time launchers loaded.
