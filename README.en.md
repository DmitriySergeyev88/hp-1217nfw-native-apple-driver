# HP M1130 / M1210 / M1217 — Native Print & Scan for Apple Silicon

[Русский](README.md) · [Download the unified installer](dist/HP-M1217-Native-Print-Scan-0.3.0-arm64.pkg) · [SHA256](dist/SHA256SUMS)

**Version 0.3.0:** a unified native printing and scanning package for Apple Silicon Macs. No Rosetta, Intel HP drivers, HPLIP or end-user Python installation. Independent project, not an official HP driver.

## Features

- Fast image printing from **Cmd+P** through the separate **HP M1217 PCLm 600** queue: A4, 600 dpi, 8-bit grayscale, JPEG strips inside PCLm.
- Fixed hangs in our PCLm jobs by accommodating the firmware's numeric parser and strip field ordering.
- Fixed `expected URF raster` in the actual Cmd+P pipeline. The native filter invokes Apple's rasterizer with the correct internal format.
- Flatbed and ADF scanning, color/grayscale, PDF/JPEG/PNG output.
- Multiple sheets or batches merged into one PDF, with a user-selected filename.
- **Fixed color distortion when scanning multipage PDFs.** Included based on the owner's confirmation; no additional color test was performed for this release.
- Native ICA integration with **Image Capture** and the **Open Scanner…** button on the new print queue.
- Existing drivers and queues are preserved; the default printer is not changed automatically. No firmware updates.

## Compatibility: models and current firmware

| Model / environment | Status |
|---|---|
| **HP LaserJet Professional M1217nfw MFP**, Ethernet, firmware **20200618** | PCLm 600 dpi, correct A4 size and Cmd+P printing confirmed; the owner reports a substantial speed improvement |
| **HP M1130 / M1210** families, firmware package branch `LJM1130_M1210_M1217_FW_Update_Security` | Compatibility candidates, **not tested on these models**. Sharing a firmware package name does not prove identical protocols |
| USB-only variants | **USB transport is not supported** by this release. Network IPP/PCLm and Marvell2 scanning are required |
| Apple Silicon, macOS **27.2** | Actual development and hardware-test environment |
| macOS **11 and later**, Apple Silicon | Build/installer deployment target is 11.0; other versions need validation. **Not a guarantee of compatibility with every macOS version** |
| Intel Macs, macOS 28 | Not tested; Intel is not supported by this arm64 package |

The tested MFP reports main image **20200618** and Print component **20201023** after updating. These are not claims about the latest firmware available for every model. Earlier scanner tests also used 20110826; the fast PCLm path was confirmed on 20200618. Firmware is not bundled or installed.

## Installing on another Mac

1. Connect a compatible MFP over Ethernet and find its IPv4 address. Reserving the address in your router is recommended.
2. Download **HP-M1217-Native-Print-Scan-0.3.0-arm64.pkg**, verify its SHA256 and install it.
3. Open **Applications → HP M1217 Setup**, enter the IPv4 address and authorize queue configuration. No author-specific IP is hardcoded and no test jobs are sent.
4. Allow **Local Network** access for Setup, Native ICA and Native Scan when prompted. If the scanner has not appeared yet, run Setup again after granting access.
5. Select **HP M1217 PCLm 600** in Cmd+P. Scan using **HP M1217 Native Scan** or Image Capture → **HP M1217 Native ICA**.
6. Keep **HP M1217 ICA Discovery** (the **HP Scan** menu) running for ICA discovery. Open it after login or add it to macOS Login Items yourself. The installer does not add a hidden background service.

The installer **refuses to overwrite existing components**. Close applications and preserve the existing components before installing another version. It does not remove an existing user copy in `~/Applications`.

The package is not Developer ID signed or notarized. Executables have ad-hoc signatures. If macOS blocks it, use the normal Privacy & Security approval flow only if you trust the release. Disabling system protection is unnecessary.

## Printing and quality

Printing is A4, grayscale, 600 dpi, single-sided. Choose layout and scaling in the source application. Rasterization to 600 dpi preserves physical size but does not create additional source detail. The native filter uses Apple ImageIO JPEG quality 0.90: this is lossy compression, not pixel-identical preservation of tones. Direct 300 dpi PCLm raster prints at half the linear size on the tested MFP and is not used by the queue.

One 4.95 MB, 600 dpi PCLm control file took **0.21 s** to prepare, **23.53 s** to transmit and receive the Print-Job response; completion was observed at **33.60 s**. This was a manual Python-prototype trial. The owner subsequently confirmed correct, substantially faster Cmd+P printing with the native queue. That print was not separately timed, and no precise speedup ratio is claimed.

## Scanning

Flatbed: color/grayscale at 75/150/300/600 dpi. ADF: color at 75/150/300 dpi. In the standalone app, use “Scan / add pages…” followed by “Save PDF…” to combine batches, up to 100 pages. In Image Capture, select PDF and “Combine into single document.” Do not open two scanner sessions simultaneously.

The separate Scan Results window may remain empty even when files are saved. Color calibration and precise edge coverage are not certified. No OCR or duplex ADF; not every settings combination has been tested. Scanning requires network Marvell2 on TCP 8290.

Scans, `capture.asp` and diagnostic logs stay local. Raw captures contain document images: do not publish them in issues. Exclude passports and other personal documents from diagnostic archives.

## Build, validation and rollback

Sources: [printing](printing/pclm), [scanner](scanner), [unified package](unified). Building requires Apple Silicon, Command Line Tools and Python 3. Pillow/pypdf are needed only for printing tests.

```sh
python3 unified/build.py
python3 printing/pclm/test_filter.py
python3 unified/test_package.py
```

Building does not install drivers or contact the MFP. See [TESTING.md](TESTING.md) for evidence and limitations.

To roll back, close scanner applications and finish print jobs. Run `/Library/Printers/HPNative1217PCLm/uninstall.sh` as administrator. It removes only the new queue and moves the components to `/Users/Shared/HP-M1217-backup-<timestamp>`. Scan documents, old drivers, original AirPrint and user-installed app copies remain intact. To restore, move the saved components back and run Setup again.

MIT license; ICA also includes Apple's sample-code license notice. HP firmware images are not included in the repository or installer.
