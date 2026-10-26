# EWF Acquire GUI (WIP)
GUI front end for _ewfacquire_ on MacOS, running on Apple Silicon (Intel not supported). Always use a Write Blocker!

SwiftUI front end for libewf's `ewfacquire`. It lists disks, builds the command line from form fields,
runs it with administrator rights, and shows live progress and the resulting hashes.

Requires _libewf_ to be installed separately. _Homebrew_ provides a quick and easy way to do this:
```bash
brew install libewf            # provides ewfacquire
```
_EWF Acquire GUI_ can be installed from the DMG file provided in the releases section of this repository, or alternatively by downloading the _source_ ZIP file and building using the instructions provided below.

## Build from source
Download the _source_ release, extract and open _Terminal_ in that location. Then:
```bash
xcode-select --install         # if you don't have Xcode / CLT yet
chmod +x build_app.sh
./build_app.sh                 # native Apple Silicon (arm64) app
```
Finally, move the _EWF Acquire GUI.app_ to your **/Applications** folder (or other location as you see fit!)

## Using it
1. **Source**: pick a disk (the raw node `/dev/rdiskN` is used), or choose an image file.
2. **Destination**: folder and image name. The app refuses to write onto the disk being acquired.
3. **Case information**: case number, evidence number, examiner, description, notes (all optional).
4. **Image options**: format, compression, extra hashes (MD5 is always computed), media type/flags;
   *Advanced* has segment size, chunk size, error granularity, read retries, zero-fill on error, resume, log.
5. **Start Acquisition**: macOS asks for your admin password; progress and hashes appear below.
   *Command preview* shows the exact `ewfacquire` command (copyable) for your case notes.

## How it works
- Reading raw devices needs root. The app launches `ewfacquire` through `osascript … with administrator
  privileges` (the standard macOS password prompt). Only the `ewfacquire` command (and an optional
  `diskutil unmountDisk`) runs as root; the GUI itself does not.
- Output is written to a private temp log (`0700` folder) that the app tails for progress.
- **Cancel** creates a flag file the root wrapper watches; it then sends `SIGTERM` to `ewfacquire`
  (no second password prompt). The partial image stays on disk; use *Resume* to continue it.
- Closing the app window does not stop a running acquisition.
- `ewfacquire` is always run with `-u` (unattended), so every setting must come from the form.
- The compression argument adapts to your libewf version (`deflate:fast` vs. `fast`).

## Practical notes
- If `ewfacquire` reports *Operation not permitted* on the device, grant the app **Full Disk Access**
  (System Settings → Privacy & Security → Full Disk Access) and retry.
- For evidentiary work, use a hardware write blocker. Unmounting volumes reduces accidental writes but is
  not a write block, and macOS can still touch media on attach.
- The startup disk of recent Macs (SIP / sealed system volume, APFS containers) cannot be imaged
  meaningfully while running from it. Boot from external media or use target disk mode.

## Troubleshooting
- **"Operation not permitted" from ewfacquire**: macOS privacy protection (TCC) is blocking the root process.
  Add the app you launched from (EWF Acquire GUI.app, or Terminal/iTerm when using `swift run`) under
  System Settings → Privacy & Security → Full Disk Access, then quit and reopen it. Downloads, Desktop and
  Documents are protected folders; `/Users/Shared` is not, which makes it handy for test files.
- **E01 files as a source**: ewfacquire only reads raw sources (disks, `.dd`/`.raw`). The app refuses E01-style
  files; use `ewfexport` to convert existing EWF images.
- Quick test source: `dd if=/dev/urandom of=/Users/Shared/test.raw bs=1m count=64`

## Image formats
Only the formats this tool targets are offered: **EWF** (.e01), **EWFX** (.e01) and **S01 / SMART** (.s01).
Default is EWF.

## .
