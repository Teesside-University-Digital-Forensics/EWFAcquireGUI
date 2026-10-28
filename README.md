# EWF Acquire GUI (WIP)
GUI front end for `ewfacquire` on _macOS_, running on Apple Silicon (Intel not supported). Always use a Write Blocker!

SwiftUI front end for libewf's `ewfacquire`. It lists disks, builds the command line from form fields,
runs it with administrator rights, and shows live progress and the resulting hashes.

Requires _libewf_ to be installed separately. _Homebrew_ provides a quick and easy way to do this (other methods are available):
```bash
brew install libewf            # provides ewfacquire
```
`EWF Acquire GUI` can be installed from the DMG file provided in the releases section of this repository, or alternatively by downloading the _source_ ZIP file and building using the instructions provided below.

## Permitting the pre-built to run on your system
When first attempting to run the app, you may encounter problems as a result of Apple's _GateKeeper_ blocking it. This can be overcome by either going to `Settings >> Privacy & Security` and scrolling down to the `Security` section, locating the entry for the `EWF Acquire GUI` app and clicking `Open Anyway`, or alternatively, by entering the following command into `Terminal`:
```bash
xattr -dr com.apple.quarantine "/Applications/EWF Acquire GUI.app"      # assumes app installed into default location; change the path accordingly if installed somewhere else 
```

## Build from source
Download the _source_ release, extract and open _Terminal_ in that location. Then:
```bash
xcode-select --install         # if you don't have Xcode / CLT yet
chmod +x build_app.sh
./build_app.sh                 # native Apple Silicon (arm64) app
```
Finally, move the newly-created `EWF Acquire GUI.app` to your `/Applications` folder (or other location as you see fit!)

## Using it
1. **Source**: pick a disk (the raw node `/dev/rdiskN` is used), or choose an image file.
2. **Destination**: folder and image name. The app refuses to write onto the disk being acquired.
3. **Case information**: case number, evidence number, examiner, description, notes (all optional).
4. **Image options**: format, compression, extra hashes (MD5 is always computed), media type/flags;
   *Advanced* has segment size, chunk size, error granularity, read retries, zero-fill on error, resume, log.
5. **Start Acquisition**: _macOS_ asks for your admin password; progress and hashes appear below.
   *Command preview* shows the exact `ewfacquire` command (copyable) for your case notes.

## How it works
- Reading raw devices needs root. The app launches `ewfacquire` through `osascript … with administrator
  privileges` (the standard _macOS_ password prompt). Only the `ewfacquire` command (and an optional
  `diskutil unmountDisk`) runs as root; the GUI itself does not.
- Output is written to a private temp log (`0700` folder) that the app tails for progress.
- **Cancel** creates a flag file the root wrapper watches; it then sends `SIGTERM` to `ewfacquire`
  (no second password prompt). The partial image stays on disk; use *Resume* to continue it.
- Closing the app window does not stop a running acquisition.
- `ewfacquire` is always run with `-u` (unattended), so every setting must come from the form.
- The compression argument adapts to your libewf version (`deflate:fast` vs. `fast`).

## Practical notes
- If `ewfacquire` reports *Operation not permitted* on the device, grant the app **Full Disk Access**
  (System Settings → Privacy & Security → Full Disk Access) and retry. NB: you must grant Full Disk Access for both the `EWF Acquire GUI` and also the `ewfacquire` package, as shown here:
<img width="479" height="128" alt="FDA" src="https://github.com/user-attachments/assets/1cff1011-db4e-4f31-9f6c-59c9782dca0e" />

- For evidentiary work, use a hardware write blocker. Unmounting volumes reduces accidental writes but is
  not a write block, and _macOS_ can still touch media on attach.
- The startup disk of recent Macs (SIP / sealed system volume, APFS containers) cannot be imaged
  meaningfully while running from it. Boot from external media or use target disk mode.

## Troubleshooting
- **"Operation not permitted" from ewfacquire**: _macOS_ privacy protection (TCC) is blocking the root process.
  Add the app you launched from (EWF Acquire GUI.app, or Terminal/iTerm when using `swift run`) under
  System Settings → Privacy & Security → Full Disk Access, then quit and reopen it. Downloads, Desktop and
  Documents are protected folders; `/Users/Shared` is not, which makes it handy for test files.
- **E01 files as a source**: ewfacquire only reads raw sources (disks, `.dd`/`.raw`). The app refuses E01-style
  files; use `ewfexport` to convert existing EWF images.
- Quick test source: `dd if=/dev/urandom of=/Users/Shared/test.raw bs=1m count=64`

## Image formats
The following forensic image formats are offered: **EWF** (.e01), **EWFX** (.e01) and **S01 / SMART** (.s01).
Default is EWF.

NB: **EWFX is NOT Ex01**

## Acquisition log
When "Write detailed acquisition log" is ticked (default), `<image>.log` is written alongside the created image file. The log contains:
1. A statement that the acquisition was produced with `EWF Acquire GUI`, with its version, plus the
   `ewfacquire` version, executable path and macOS version.
2. Source, destination, **case information** (section 3) and **image options** (section 4), including the
   options selected in the advanced settings menu.
3. The exact `ewfacquire` command, as shown in *Command preview* section of the GUI.
4. Run details: start and end time (local and UTC), result and exit code.
5. ewfacquire's own log (`-l`) and its console output with the progress lines removed (hashes, errors).

The log is assembled by the same privileged script that runs `ewfacquire`, so it is completed even if the
app is closed mid-run. It is handed back to your user account (`chown`) once written.

## Cancelling
**Cancel** stops `ewfacquire` without a second password prompt. The result is decided from the exit code, whether
you asked to cancel, and ewfacquire's own `SUCCESS` / `FAILURE` / `ABORTED` line, so a cancelled run is shown (and
logged) as *Cancelled*, not as a failure or a success. If ewfacquire does not stop within 15 seconds (for example a
hung USB read) it is force-stopped. The partial image stays on disk.

## .
