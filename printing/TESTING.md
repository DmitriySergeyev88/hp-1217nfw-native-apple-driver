# Offline verification — 2026-10-30

Scope: local arm64 build only, macOS 27.2. No queue installation, IPP access or print job submission. Existing scanner and print components are not modified.

- PASS: 12 automated tests. Independent system libcups decoding; exact pixel and page-header comparison; shortest packet sizes checked against a brute-force reference; row repetition boundaries; multiple pages; malformed/truncated input; unknown page counts; CUPS filter ABI; broken output pipe; cancellation while input is blocked; full 600 dpi A4 noise page; PDF-to-filter CUPS chain; Letter with landscape request; PPD syntax validation; root:wheel/0755 executable ownership and mode in the installer BOM; installer payload and existing-file/symlink guards.
- PASS: AddressSanitizer + UndefinedBehaviorSanitizer, 80 valid and 160 malformed synthetic streams, widths up to 12000 pixels.
- PASS: arm64-only executable, ad-hoc signature, installer build and SHA256 manifest.
- NOT RUN: actual installation, CUPS scheduler sandbox execution, physical compatibility, speed, page measurements and printed tonal quality. No claim of macOS 28 support.

Measured examples (not printer timings):

| Synthetic input | Before | After | Meaning |
|---|---:|---:|---|
| Two-page A4 PDF through Apple renderer | 18,892 B | 18,892 B | Identical headers and pixels; no size reduction |
| Short repeated-run pattern encoded first by system CUPS | 6,246 B | 5,044 B | ~19.2% smaller for this selected pattern; not a photograph |
| Full A4 pseudorandom noise, 4960×7015, 600 dpi, literal URF | 35,075,044 B | 35,074,898 B | Negligible reduction; noise is not a photographic benchmark |

Latest local encoding times and byte counts are regenerated in `build/*comparison.txt`. They exclude printer transfer and processing. The native encoder does not promise to fix a ten-minute image print: lossless URF has limited compression opportunities.

Initial checks exposed an incorrect test expectation of A4 raster dimensions (the actual Apple renderer emits 4960×7015) and inherited PPD Manufacturer/ShortNickName conformance errors. The test expectation and PPD identifiers were corrected; final tests passed. The package's final absolute filter path is intentionally absent before installation; PPD validation skips installed-filter checks (-I filters); local builds belong to the developer, while package BOM independently verifies the installed executable will be root:wheel/0755. Nothing is installed for this check.
