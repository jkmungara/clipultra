# Changelog

Versions follow [semantic versioning](https://semver.org/).

## 1.0.1 (2026-11-12)

- **Faster:** the clipboard is checked every 0.02 s instead of every 0.1 s. A new screenshot now
  waits about 10 ms on average before compression starts, instead of about 50 ms. A check reads
  only the clipboard's change counter (about 1 microsecond), so this costs about 0.2% more of
  one CPU core.
- `--interval` accepts 0.01 to 10 seconds. The start-up log line shows the interval.

## 1.0.0 (2026-11-12)

First release. It replaces the earlier single-file clipultra script.

- **Only screenshots are touched.** clipultra acts only when the clipboard holds a single image
  and nothing else. Spreadsheet cells, pictures copied from a web page and files copied in Finder
  keep their text, HTML or file link.
- **Tall captures stay readable.** Only the width is limited (default 2560 px), not the longest
  side. A 3456×27260 full-page capture becomes 2560×20193, not 203×1600.
- **No copies on the Desktop** unless `--save-dir <folder>` is given. A saved file is never
  overwritten.
- **Fixed:** a screenshot copied while another was still being compressed was never compressed.
- Never overwrites something copied while an image is being compressed. Never replaces an image
  with a larger JPEG. Never compresses its own output.
- Transparent areas become white; colour profiles are kept; images too tall for JPEG are left as
  they are.
- Options: `--quality`, `--max-width`, `--min-kb`, `--save-dir`, `--interval`, `--verbose`.
- The log is written line by line, so a log file never ends mid-line.
- `make install` / `make uninstall` set up a launchd service that starts at login.
- Swift Testing suites with a fake clipboard and private pasteboards. They never use your
  clipboard.
