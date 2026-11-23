# Changelog

## v2.2.2

### New
- **Animated GIFs.** Choose a `.gif` file when you add a picture (**Choose a picture file...**) and it stays animated. The shortcut pastes it as a file, the same as copying it in File Explorer and pressing Ctrl+V, so it keeps moving in Gmail, Google Voice, Slack, Teams and Discord. Outlook attaches it.
  - The preview shows the GIF's first frame, its number of frames and its size, with **Save (moving)** or **Still picture instead**. Use a still picture for Word and other places that can't show a GIF moving.
  - **Shrink for GIFs.** Text messages (Google Voice included) often refuse GIFs over about 600 KB. Those GIFs get a clear warning and a **Shrink** button, which makes a smaller copy that still moves: no wider than 480 pixels (a phone screen), then smaller, then fewer frames, until it fits. A big GIF can take up to a minute; a note shows the progress. The limit can be changed in `prefs.ini` under `[Images]` (`GifTargetKB`).
  - In the text a GIF is written `{image:name.gif}`. **Replace Picture...** can swap a still picture for a GIF or the other way round; click Save to keep the change.
- Same safety rules as pictures: GIFs are kept in the `images` folder, `{image:}` only reads from there, only real GIF files are used (checked by their first bytes), the pasted GIF stays out of clipboard history and the cloud clipboard, your clipboard comes back afterwards, and Enter is never pressed for you.

## v2.2.1

### Changed
- **A tidier Add Text Expansion window.** It's wider, and every button label fits on one line (the date buttons were cut off before).
  - The date and time buttons show today's date and time as examples (for instance **2026-11-20** or **7:34 PM**). They still fill in the date and time when the shortcut is used.
  - **Add Picture...** sits with the other insert buttons.
  - New buttons: **Fill-in spot** (after the text is typed, your cursor waits there so you can fill in a name or detail), **Ask a question** and **Clipboard text**.
  - Rest the mouse on any of these buttons to see what it does.
  - The long list of codes moved behind **More...**, where nothing is cut off. It now includes pictures.

## v2.2.0

### New
- **Picture shortcuts.** A text expansion can now paste a picture: snip part of the screen once, then type a short shortcut to paste it into an email, chat or text message. Good for a logo, a product photo, a flyer, or a payment or Wi-Fi QR code.
  - **Tray menu → Add a Shortcut → Picture (snip or file).** Name the shortcut, then snip the screen, use the picture already on the clipboard, or choose a picture file. The text window opens with the picture in it, so you can add words before or after it (`Here's the one I'd look for: {image:magnesium.png}`).
  - **Add Picture...** in the Add Text Expansion and Edit windows puts a picture where the cursor is.
  - **Replace Picture...** in the Edit window swaps in a new picture under the same name, so an updated flyer keeps its shortcut.
  - In the text, a picture is written `{image:name.png}`. Other placeholders such as `{date}` work next to it.
- **You see the picture before it's saved**, with its size. If it's large for a text message (wider than 1200 pixels or bigger than about 1 MB), MultiShortcuts says so and offers **Shrink** (1000 pixels wide). Or zoom out in the app first (Ctrl and minus) and **Retake**: small text often stays sharper that way. The limits can be changed in `prefs.ini` under `[Images]` (`WarnWidth`, `WarnKB`, `ShrinkWidth`).
- A picture pastes wherever you can paste a picture yourself: Gmail, Outlook, Word, Google Docs, Teams, Slack, Discord, Google Voice and similar. Plain text boxes such as Notepad can't take one.

### Safety and privacy
- Pictures are kept in an `images` folder next to `MultiShortcutsPro.ahk`. `{image:}` only reads from that folder: a plain name of letters, digits, `-` and `_` ending in `.png`. Folders, `..`, drive letters and network paths are refused, so a shortcut (or an imported file) can't make MultiShortcuts read any other file. Only real PNG files are used, up to 10 MB.
- Every picture is saved as a fresh PNG when you add it. That also removes hidden photo details such as the camera, date and GPS location. Phone photos are turned the right way up first.
- A pasted picture gets the same clipboard protection as text: it's kept out of clipboard history (Win+V) and cloud clipboard, and your old clipboard is put back afterwards. This also applies with **Type expansions directly** on, because a picture can't be typed key by key.
- **A shortcut with a picture never sends Enter for you.** If you end it with Enter, the Enter isn't re-sent, so a chat or text message isn't sent before you've checked what's attached.
- Pictures you add in a window and then cancel are deleted again. Deleting a shortcut leaves its picture in the `images` folder.

### Notes
- Backups and CSV export/import cover the shortcut text only. To move picture shortcuts to another PC, copy the `images` folder too.
- Picture shortcuts don't move to the phone with the Phone ↔ PC converter.

## v2.1.10

### New
- **Commands on the space bar.** With **Hold for symbols** on (tray menu → Settings → Space bar), hold Space and tap:
  - **F** to add a text expansion, the same as Alt+T (F for Fast)
  - **C** to capture the selected text as a shortcut, the same as Alt+C
  - **V** for a screen clip, the same as Alt+Shift+S (V looks like open scissors)

  The command starts when you let go of Space, so its window never opens while you're still holding keys. Esc during the hold cancels it. F and C need Full mode; in Starter mode they type normally. All the Alt keys still work.

### Changed
- **Space + B is Backspace now** (B for Back). It was Space + R, which is now free.
- **Space + Y types `^` now.** Y sits right under the 6 key, and `^` is Shift+6. It was Space + C, which now captures, like Alt+C.
- Space + X (delete the last word) and Space + Z (undo the last expansion) are unchanged.
- **A shorter tray menu.** It had grown to 36 lines; now it has 8: **Add a Shortcut**, **Edit Shortcuts**, **Snip**, **Pause/Resume**, **Settings**, **Tools**, **Help** and **Exit**. Everything else is one level down:
  - **Add a Shortcut:** Text Expansion, App Launcher, Document, Web/Email, Capture Selection
  - **Settings:** Run on Windows Startup, Sound Feedback, the hold keys, Caps Lock, Space bar, Middle mouse button, Hold Keys Timing, Trigger Keys Setup, Shortcut Triggers and **Privacy** (Type expansions directly, Hide expansion text, Alt+C capture)
  - **Tools:** Quick Expansion Picker, Undo Last Expansion, Usage Statistics, Backup Now, Export and Import CSV, Key Check, Release Stuck Keys, Reload Script
  - **Help:** Quick Start, Show Help

  Starter mode has the same Settings, Tools and Help menus.

### Fixed
- The Quick Start no longer lists the space bar's Backspace / delete word / undo keys when the space bar option is off.

## v2.1.9

### Fixed
- **Ending keys are kept.** A shortcut ended with Enter, Tab or punctuation now keeps that key: `addr` + Enter makes a new line, and `addr,` / `addr.` keep the comma or period. Before, the key was replaced by a space.
- **No double space.** An expansion whose text already ends in a space (`Dear `) no longer gets a second one.
- **Quick Expansion Picker (Alt+Q)** now fills in `{date}`, `{clip}`, `{cursor}`, `{prompt:}` and `{key:}` like a typed shortcut. Before, it typed them as written.
- **CSV import asks once per launcher.** The review window now shows the "powerful system program" warning, and the separate yes/no questions for the same launcher are gone.
- **Very old shortcut files** in the `shortcut|text` format whose text has spaces (`addr|123 Main St`) are now converted. Before, those lines were skipped and then failed to load. A dated backup is made first.
- **{clip} safety warning** shows the text around the risky part, not just the start of the clipboard.

## v2.1.8

### New
- **Save as New in Edit Shortcuts.** Open a shortcut with **Edit** (or double-click it), change the name and anything else, then click **Save as New** (Alt+N). The changed copy is added under the new name and the original stays exactly as it was. Handy for making `sig2` from `sig`, or a second address from the first.
  - The new name can't be one that another shortcut already uses, and it has to differ from the original's name. Nothing is changed if it does.
  - **Fire instantly** on the copy follows the box in the Edit window. The original keeps its own setting.
  - A launcher copy gets the same checks as any new launcher: `ftp://` is refused and `http://` asks first.
  - **Save** works as before: it changes (or renames) the shortcut you opened.

## v2.1.7

### Changed
- **Undo removes the whole expansion.** Alt+Z and Space + Z now take out the expansion and leave nothing in its place. Before, they typed the shortcut back (`addr`), which you didn't want when an expansion fired by accident. A `. , ! ?` that Auto Spacing moved after the expansion goes with it.

## v2.1.6

### New
- **Fix typos from the space bar.** With the space bar set to **Hold for symbols**, hold Space and tap **R** for Backspace (R for Remove), or **X** to delete the whole last word (X to cross it out). Keep holding the letter and it repeats. The 19 symbols are unchanged.
- **Undo an expansion from the space bar.** Hold Space and tap **Z** to undo the last expansion, the same as Alt+Z: it puts back what you typed. It undoes one expansion per hold, even if you keep holding Z.
- Like the symbols, it only starts after Space is held alone for a quarter second, so fast typing is never affected. With **Hold for Shift**, R and X still type capitals.

## v2.1.5

**A change in default behavior:** shortcuts now use the same trigger rules as SpeedKee on your phone, so more of them fire without a space. Each rule can be turned off in the tray menu under **Shortcut Triggers**. All of them are on by default.

### Shortcut Triggers
- **Double Tap:** type the last letter twice and the shortcut expands at once (`addr` → type `addrr`). The space-or-Enter way still works.
- **Number:** a name that ends in a digit fires at once (`sig2`, `1m`).
- **Almost Auto:** a name with a digit or symbol after its first character (`a.b`, `x-ray`), or one ending in a capital (`xN`), fires at once. A symbol only at the start (`!note`) doesn't count.
- **Auto ($$):** a name ending in `$$`, or with **Fire instantly** ticked, fires at once, as before.
- **Auto Capitalization:** type a shortcut with a capital first letter (`Addr`) and the text starts with a capital.
- **Auto Spacing:** type `. , ! ? ;` or `:` right after an expansion and the extra space disappears: `123 Main St .` becomes `123 Main St. `. If you click, switch windows or press an arrow key first, nothing is changed.
- Swipe 2-letter is a phone-only trigger.
- Instant shortcuts still never fire from the middle of a word. They can fire at the start of one, though: with Double Tap on, a shortcut `ad` also fires when you type `add` or start typing `address`. Rename it, or turn Double Tap off.
- A form that's already the name of another shortcut is never taken over. For example, if `Addr` is its own shortcut, Auto Capitalization leaves it alone.
- **Undo (Alt+Z)** puts back exactly what you typed (`Addr`, `addrr`, `addr.`).
- When you upgrade, a one-time message explains the new rules. **Tray menu > Shortcut Triggers > About Shortcut Triggers** shows it again.

## v2.1.4

### New
- **Edit Shortcuts: Copy Selected and Export Selected…** Select one or more shortcuts (Ctrl+click to add or remove one, Shift+click for a range):
  - **Copy Selected** puts them on the clipboard as plain lines, easy to paste into an email or message: the shortcut, a space, then its full text (for example `` `2 https://mail.google.com ``). Everything is copied exactly as stored: `{clip}`, `{key:…}` and the rest are kept as written, never run. Line breaks inside a text show as `[NEWLINE]`, and Fire instantly as `$$`.
  - **Export Selected…** saves them to a `.csv` file you choose, in the same format as Export to CSV, so anyone can bring them in with Import from CSV.
  - The copy is kept out of Windows clipboard history and cloud clipboard, like the program's other pastes.

## v2.1.3

A security update, plus two new conveniences. Your shortcuts and settings are kept, and the launchers you already have keep working.

### Security
- **Importing a CSV file:** a launcher is no longer imported automatically if it starts a program (`.exe`), opens a Windows shortcut (`.lnk`), points to another computer or network share, opens another app's link (such as `zoommtg:` or `steam:`) or uses an unencrypted `http://` address. You see each one, with the full path, what a `.lnk` really opens and any extra instructions, and decide one by one. **Skip** is the default. A network path is shown before anything checks it, because checking it already makes Windows connect to that computer. Website (`https://`), email, document and folder launchers import as before.
- **New launchers:** `ftp://` addresses are refused (they aren't encrypted). An `http://` address is added only after you confirm it, and Alt+W offers to switch it to `https://`. Launchers you already have with these addresses still work, and can still be renamed.
- The Alt+T window and the help screen now say that shortcuts are saved on your PC as readable text, so they shouldn't hold passwords, 2FA codes or other secrets.

### New
- **Hold the space bar for Shift** (tray menu, **Space bar**, off by default). The space bar has three choices:
  - **Off:** a normal space bar.
  - **Hold for symbols:** Space + J = `!`, as before.
  - **Hold for Shift:** hold Space, wait a moment, then type, and the space bar works like Shift: Space + a = A, Space + 1 = `!`. Keep holding it for a whole word in capitals.

  A quick tap is a normal space and fast typing is safe: Space only becomes Shift or symbols after it's held alone for a quarter second. If you used Space Symbols before, it stays on as "Hold for symbols".
- **Ctrl+Alt+Space** steps through the three space bar choices: Off → symbols → Shift → Off. A small note next to the text cursor says which one is on.
- **Edit Shortcuts: delete several at once.** Ctrl+click to add or remove shortcuts one at a time, or Shift+click to select a range, then click **Delete**. You see every name before anything is deleted, and **No** is the default. Edit and Test still work on one shortcut at a time.

### Fixes
- **Edit Shortcuts:** closing the window while a "Delete …?" question was open showed an error ("The control is destroyed"). The question now belongs to the window, so the window can't be closed until you answer.
- **Edit Shortcuts:** after a delete, the list keeps your search instead of showing everything again and jumping back to the top.

## v2.1.1

A fix for keys and clicks that could stop working, plus two keyboard shortcuts for getting out of trouble. Your shortcuts and settings are kept.

### Fixes
- **Ctrl or Alt no longer gets stuck down after a hold.** Windows hides your keys and clicks from MultiShortcuts while a program running as administrator is in front (Task Manager, an installer, some app updaters such as Zoom's), and while the lock screen, a Windows "allow changes?" prompt or Ctrl+Alt+Del is up. If you let go of Caps Lock, `` ` ``, `;` or the middle button at that moment, MultiShortcuts never saw it, so Ctrl or Alt stayed down. Every click then became Ctrl+click or Alt+click: a link opened in a background tab, or a file click only changed the selection. Now the hold ends as soon as one of those windows comes up, and a small notice says why.
- **Shift + middle click** can no longer leave the middle button held down in the same situation.
- **Clicking or scrolling while holding a hold key** no longer types its character when you let go. Holding `;` to Ctrl+click files used to add a `;`.

### New
- **Ctrl+Alt+Shift+K - Key Check.** Shows whether any key or mouse button is stuck down, which program is in front, and whether other AutoHotkey scripts are running (such as a second copy of MultiShortcuts). If something is stuck, it offers to release it. Press it the moment clicks or keys act strangely. Ctrl+C copies the message.
- **Ctrl+Alt+Shift+R - Release Stuck Keys.** Lets go of Ctrl, Alt, Shift, Win and the mouse buttons at once.
- Both work without the mouse, in Starter and Full modes, and even while MultiShortcuts is paused. Both are also in the tray menu.

## v2.1.0

### New
- **"Fire instantly" for your own shortcuts.** Every window that adds or edits a shortcut (Alt+T, Alt+A, Alt+D, Alt+W, Alt+C and the editor, Alt+E) has a **Fire instantly - no space needed ($$)** box. Ticked, the shortcut fires as soon as you finish typing it. Unticked, it waits for a Space or Enter. Typing `$$` at the end of the name does the same as ticking the box. It's the same `$$` rule SpeedKee uses on the phone, so a shortcut behaves the same on both devices.
- **Hold Space for symbols** (tray menu, off by default). Hold the space bar and tap a letter for a symbol that's normally a Shift-stretch away:

  | Key | Symbol | Key | Symbol | Key | Symbol |
  |---|---|---|---|---|---|
  | J | `!` | K | `?` | L | `"` |
  | G | `(` | H | `)` | M | `-` |
  | P | `+` | T | `%` | I | `:` |
  | Q | `?` | A | `@` | E | `=` |
  | D | `$` | S | `*` | N | `&` |
  | U | `_` | C | `^` | , | `<` |
  | . | `>` | | | | |

  A quick tap of Space is a normal space, and fast typing is safe: Space only becomes the symbol key after it's held alone for a quarter second. Ctrl, Alt and Shift + Space work as usual (hold Caps Lock + Space for the window menu). Symbols set off your shortcuts just like typed ones, so hold Space + J J can fire a `!!` shortcut. Ticking the option shows the full list; Alt+H shows it too.

### Changed
- **Your own shortcuts fire instantly only with `$$`** (the Fire instantly box). Before, a shortcut with a digit or a symbol, or ending in a capital letter, fired instantly on its own. Now everything else waits for a Space or Enter, so shortcuts can't misfire inside normal words. The built-in `;`, `` ` `` and `=` families are instant as always.
- **Nothing changes for your existing shortcuts.** On first start, v2.1.0 adds `$$` once to every shortcut of yours that fired instantly under the old rule, and tells you how many it updated.
- **Launchers understand `$$` too**, and keep it through edits, exports and trigger-key changes.
- The Alt+C warning now says not to capture **confidential text** (passwords, account numbers, patient or client details).

### Fixes
- **Alt no longer gets stuck** after an Alt command (Alt+T, Alt+E…) pressed by holding Caps Lock, `` ` `` or `;`. The window that opened couldn't be typed in until you tapped the real Alt key.
- **Edit Shortcuts:** the Target and Expands To columns are always wide enough to read.
- **Edit Shortcuts:** ticking or unticking Fire instantly takes effect at once, without a reload.
- `abc` and `abc$$` can no longer end up as two copies of the same shortcut, one of them hidden.
- A `{key:`, `{wait:` or `{focus:` that is never closed is typed as text, never run, and the rest of the expansion is read normally.
- The clipboard is never left locked, even after an unexpected error while setting private text.
- Every Ctrl, Alt, Shift and Win key is released on exit or reload, so a reload can't leave one held down.
- The editor lists select one row at a time. (Since v2.1.3, several rows can be selected for Delete.)

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
