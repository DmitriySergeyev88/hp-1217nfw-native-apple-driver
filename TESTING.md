# Validation — unified release 0.3.0

Actual host: macOS 27.2, Apple Silicon. Build/installer deployment target: macOS 11.0; no claim of runtime verification on other versions. Firmware used for the successful PCLm trial: main 20200618 / Print 20201023, HP M1217nfw over Ethernet.

| Check | Result |
|---|---|
| Scanner C/Objective-C build and native protocol/decoder tests | PASS, offline |
| Native Scan options and PDF-session self-tests | PASS, offline |
| ICA capabilities, file/band delivery and discovery self-tests | PASS, offline |
| PCLm filter tests: 7 cases, including real CUPS FINAL_CONTENT_TYPE, stdin/file PDF, cancellation and malformed input | PASS, offline |
| Unified package: contents, signatures, every Mach-O arm64/minos 11.0, minimum app versions, checksums, preinstall conflict rejection | PASS, 2 tests |
| Existing app/ICA package regression checks | PASS; old released package bytes preserved |
| PCLm prototype 600 dpi hardware trial | PASS: one correctly sized A4 page, owner confirmed image, no reboot |
| Installed native queue from Cmd+P after input-format fix | PASS, owner confirmed correct output and much higher speed; not separately timed |
| Open Scanner button on that queue | PASS, owner confirmed appearance; button-triggered scan not separately tested |
| Flatbed and two-page ADF PDF | Owner-confirmed earlier in the project; not repeated for this package |
| Multipage PDF color-distortion fix | Included at owner's request/confirmation; no additional color verification for this release |
| Fresh installation and Setup on a second Mac | NOT RUN: no second Mac available |
| Installer/Setup/uninstaller against the owner's working installation | NOT RUN deliberately; existing working components preserved |
| HP M1130 / M1210 hardware | NOT RUN; not verified compatible |
| Other macOS releases, including macOS 28 | NOT RUN |

One manual PCLm prototype trial: 4,947,536 bytes, preparation 0.20894 s, Print-Job send+response 23.53024 s, completion observed at 33.60283 s with a 10-second polling interval. These are not native-queue benchmark numbers and do not establish a precise AirPrint speedup ratio.

`NativeScan --test` initially aborted inside the restricted build environment; it passed in the normal local user context. The complete final package build and self-tests then passed. The historical `cupsfilter -d` lookup failed on this host; explicit installed PPD paths and a regression test reproducing CUPS' final MIME were used. Neither limitation is hidden as a successful test.

No physical print/scan was triggered while preparing 0.3.0. Test fixtures are synthetic; no user scans, raw captures, firmware images or private diagnostic logs are included. Temporary test directories are cleaned; no development servers are required.

Reproduce with Command Line Tools and Python 3 (Pillow/pypdf for print tests):

```sh
python3 unified/build.py
python3 printing/pclm/test_filter.py
python3 unified/test_package.py
```
