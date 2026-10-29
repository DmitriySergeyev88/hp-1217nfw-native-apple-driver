# HP M1217nfw Native Apple Driver

[Русский](README.md)

Experimental **HP M1217 Native Scan** for HP LaserJet Professional M1217nfw MFP over Ethernet on Apple Silicon. Independent native Marvell2 backend; no Rosetta, HPLIP, or Intel HP libraries.

**0.2.0 is a prerelease.** This is a scanning application, not a replacement printing driver. The installer does not alter CUPS queues, ICA modules, or firmware. Experimental Image Capture integration is excluded because its results list remains unresolved.

## Features

- Flatbed and ADF over TCP 8290.
- Flatbed: color/grayscale, 75/150/300/600 dpi. ADF: color, 75/150/300 dpi.
- Custom document name; PDF, PNG and JPEG files for each capture.
- Combine multiple flatbed captures or ADF batches into one PDF, in capture order (up to 100 pages, also subject to per-capture memory limits).
- PDF pages are combined without rasterizing or scaling them again.
- Existing PDFs are never overwritten. An unsaved-document warning protects the current selection.
- Raw captures and diagnostic logs stay local. The merge selection is not restored after restarting; individual capture PDFs remain available.

## Install

Download `HP-M1217-Native-Scan-0.2.0-arm64.pkg` from [Releases](../../releases) or [dist](dist). Verify it against [SHA256SUMS](dist/SHA256SUMS).

The package installs only `/Applications/HP M1217 Native Scan.app`. It refuses to overwrite an existing app there: quit and move the old version to a backup folder first. An earlier copy in `~/Applications` is preserved; explicitly launch the new copy from `/Applications`.

The app is ad-hoc signed; the installer is **not Developer ID signed or Apple notarized**. Gatekeeper may block a downloaded package. Use the normal Privacy & Security approval only if you trust this release, or build locally. Do not disable system protection. Allow Local Network access when macOS requests it.

## Use

1. Close Image Capture and other scanning clients; the scanner supports one active session.
2. Enter the scanner's IPv4 address (remembered locally), source, resolution, mode and document name.
3. Click **«Сканировать / добавить листы…»** (Scan/add pages). On the first capture, choose a folder.
4. Replace each flatbed sheet and repeat, or load an ADF batch. Each capture is retained in a separate `part-*` folder.
5. Click **«Сохранить PDF…»** (Save PDF) to choose the final filename and destination. Choose another name if it exists.
6. **«Новый документ»** (New document) starts a fresh selection without deleting earlier captures.

The UI currently uses Russian labels. Every capture folder contains PDF/PNG/JPEG, `capture.asp`, saved scanner settings and `diagnostic.log`. Raw captures contain document images: do not post them in public issues. There is no cloud upload or telemetry.

## Verification and limitations

Hardware baseline: macOS 27.2 arm64, HP M1217nfw firmware 20110826; flatbed and one/two-page ADF at 300 dpi previously tested. Version 0.2.0 changes have offline tests for names, multi-batch PDF merging, order, page dimensions and overwrite protection. **The new GUI workflow has not yet undergone a physical scanning acceptance test.**

No claim of macOS 28, Intel Mac, or other-model compatibility. Exact A4 edge coverage and color calibration are incomplete. ADF raster dimensions can be smaller than the requested page; missing pixels are not synthesized. No duplex ADF, OCR, blank-page removal or automatic rotation. Recovery from interrupted device sessions is limited. On cleanup failure, further scanning is disabled; check the scanner and logs before restarting.

## Build and test

Apple Silicon, macOS 27.2+, Command Line Tools and Python 3 are required. No third-party libraries. The minimum OS setting is not a compatibility promise for future releases.

```sh
sh scanner/build.sh
python3 build_installer.py
```

Tests use synthetic data and never contact a scanner. Optional user-folder installation refuses to replace an existing app:

```sh
python3 scanner/install_app.py install
```

## Uninstall / rollback

Quit the app and move it to Trash; restore your backed-up version if needed. Saved documents remain in your chosen folders. There are no background services and no printing/legacy HP driver changes.

For the user-folder script installation, `python3 scanner/install_app.py rollback` moves only the validated app from `~/Applications` to Trash.

## License

MIT. Unofficial project, not affiliated with HP or Apple. No proprietary HP code or binaries are distributed.
