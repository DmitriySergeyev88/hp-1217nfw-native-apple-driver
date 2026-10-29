# Проверки / Verification — 0.2.1

2026-10-30, macOS 27.2 arm64.

| Проверка / Check | Result |
|---|---|
| Native transport/decoder self-tests and 4 synthetic Python tests | PASS |
| PDF session: Unicode names, invalid names, two/multiple batches, page order and dimensions, existing-file preservation | PASS |
| Application bundle signature and arm64-only executables | PASS |
| User-folder installer: install, refusal to overwrite, rollback in temporary folder | PASS |
| PKG expansion: only standalone app payload, signature, app self-test, existing file/symlink protection | PASS |
| New GUI workflow with physical flatbed / ADF captures | NOT RUN |
| Real system installation of this PKG | NOT RUN (payload/guard tested in temporary folders) |
| Apple notarization / Developer ID signature | NOT AVAILABLE |
| macOS 28 / Intel Macs / other scanner models | NOT RUN |

Earlier hardware tests exercised the same capture/decoder backend on flatbed and one/two-page ADF at 300 dpi. They do not substitute for acceptance testing of the new 0.2.0 GUI workflow.

The UI was constructed in an isolated no-scan process. Native view bitmap capture does not reliably render all AppKit controls; it is not counted as a successful visual acceptance test.

No personal scans, captured device traffic, private diagnostic logs or machine-specific paths are included in this repository. Tests generate their own raster streams. Release application tests never initiate a scan.

## ICA 0.2.1

- PASS: clang arm64 with warnings as errors; module capabilities, parameters and synthetic file/band delivery self-tests.
- PASS: IPv4 validation and Bonjour TXT self-test (no preferences or network changes).
- PASS: both bundle signatures and arm64-only executables; expanded package contains only the two documented apps.
- PASS: installer rejects existing files and dangling symlinks for either component, preserving contents.
- NOT RUN: installation of this ICA package, new menu-bar configuration UI and actual scanning with the configured address.
- Baseline hardware evidence from earlier development: flatbed overview/JPEG and two-page ADF PDF saved successfully. Separate Scan Results list remained empty. No claim that 0.2.1 resolves it.
- The failed progress notification change is excluded. No proprietary HP components, personal scans or device logs are distributed.

Standalone package retest initially aborted inside the restricted execution environment; rerunning the same offline test with normal local execution passed. Existing standalone and Discovery processes were left running; no new persistent process was started.
