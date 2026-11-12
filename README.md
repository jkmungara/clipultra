# clipultra

Makes screenshots on the macOS clipboard smaller. Copy a screenshot (Cmd-Ctrl-Shift-4) and
clipultra replaces the PNG with a JPEG, typically 30–90% smaller. That makes screenshots quicker
to paste into chat, email and tickets, and keeps them under attachment limits.

It acts only when the clipboard holds a single image and nothing else. Spreadsheet cells, a
picture copied from a web page and a file copied in Finder also put an image on the clipboard,
next to text, HTML or a file link. clipultra leaves those alone, so pasting still gives you what
you copied.

## Install

Needs macOS 13 or later and Xcode 16 (Swift 6) or later.

```sh
git clone https://github.com/jkmungara/clipultra.git
cd clipultra
make test       # optional: runs the test suite
make install    # builds, copies to /usr/local/bin, starts now and at every login
```

`make uninstall` removes it again. To try it without installing, run `swift run clipultra`
and copy a screenshot. Each compressed image is logged with its size before and after.

## Options

| Option | Default | Effect |
|---|---|---|
| `--quality <0.1-1.0>` | `0.85` | JPEG quality. Images over 3 MB use at most 0.85, over 8 MB at most 0.78. |
| `--max-width <pixels>` | `2560` | Images wider than this are scaled down to this width. `0` keeps the full size. |
| `--min-kb <KB>` | `300` | Images smaller than this are left alone. |
| `--save-dir <folder>` | none | Also saves each JPEG in this folder, never overwriting a file. |
| `--interval <seconds>` | `0.02` | How often the clipboard is checked (0.01 to 10). |
| `--verbose` | off | Also logs clipboard changes that were left alone, and why. |

To pass options to the installed service, add them under `ProgramArguments` in
`~/Library/LaunchAgents/io.github.jkmungara.clipultra.plist`, then run `make stop start`.
The log is `~/Library/Logs/clipultra.log`.

## What it does with each copy

| On the clipboard | Result |
|---|---|
| One PNG or TIFF image of at least 300 KB | Replaced by a JPEG, if the JPEG is smaller |
| The same, but the JPEG is not smaller | Kept as it is |
| An image plus text, HTML, a link, a PDF or a file (spreadsheet cells, web pictures, Finder files) | Kept as it is |
| Several items | Kept as it is |
| A JPEG, or clipultra's own output | Kept as it is |
| Something new copied while an image is still being compressed | The new copy is kept; the older image is not written back |

Details:

- **Only the width is limited.** A full-page capture of 3456×27260 pixels becomes 2560 pixels
  wide with readable text, not a thin strip.
- **Transparency becomes white.** For example, the shadow around a window capture.
- **Colour profiles are kept.**
- **Images too tall for JPEG are left as they are.** JPEG holds at most 65,535 pixels per side.

## How it works

clipultra checks the clipboard's change counter every 0.02 seconds. One check takes about one
microsecond, so this costs almost nothing, and a new screenshot waits about 10 ms on average
before compression starts.
It does nothing while the clipboard is unchanged. When something new is copied:

1. It reads the clipboard on the main thread.
2. It compresses the image in the background with ImageIO.
3. It writes the JPEG back only if the clipboard has not changed in the meantime.

The JPEG goes onto the clipboard with a marker type (`io.github.jkmungara.clipultra.optimized`),
so clipultra never compresses its own output.

| Path | Contents |
|---|---|
| `Sources/ClipCore/Policy.swift` | Decides whether the clipboard holds only an image (an allow-list of image types) |
| `Sources/ClipCore/Compressor.swift` | Scales and encodes the JPEG |
| `Sources/ClipCore/Watcher.swift` | Clipboard checks, the background compression, writing back |
| `Sources/clipultra/main.swift` | Command-line options and logging |
| `Tests/ClipCoreTests` | Swift Testing suites |

The tests use a fake clipboard and private, named pasteboards. They never read or change your
clipboard.

## Measured

Eight real screenshots, default settings, on an Apple Silicon Mac:

| Screenshot | PNG | JPEG | Time |
|---|---|---|---|
| Full screen, 3456×2234 (photo) | 9.5 MB | 691 KB, 2560 wide | 101 ms |
| Window, 2936×1682 | 1.5 MB | 416 KB, 2560 wide | 46 ms |
| Full-page capture, 3456×27260 | 7.4 MB | 5.1 MB, 2560×20193 | 797 ms |
| Dashboard, 1385×631 | 475 KB | 253 KB | 11 ms |
| Mostly flat colours, 2614×1414 | 499 KB | (581 KB, not smaller: PNG kept) | 39 ms |

## License

MIT
