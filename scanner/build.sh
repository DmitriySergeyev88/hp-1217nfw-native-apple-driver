#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p build
clang -arch arm64 -Wall -Wextra -Werror -O2 marvell_probe.c -o build/marvell_probe
clang -arch arm64 -Wall -Wextra -Werror -O2 marvell_capture.c -o build/marvell_capture
clang -arch arm64 -fobjc-arc -Wall -Wextra -Werror -framework Foundation -framework ImageIO -framework CoreGraphics decode_capture.m -o build/decode_capture
clang -arch arm64 -fobjc-arc -Wall -Wextra -Werror -framework AppKit -framework PDFKit -framework UniformTypeIdentifiers ScannerApp.m -o build/NativeScan
python3 test_native.py
build/NativeScan --test
python3 package_app.py
python3 test_package.py
