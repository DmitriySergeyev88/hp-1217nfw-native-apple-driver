#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as administrator' >&2; exit 1; }
[ "$#" -eq 1 ] || { echo "Usage: install.sh IPv4" >&2; exit 1; }
ip=$1
case "$ip" in ''|*[!0-9.]*) exit 1;; esac
cd "$(dirname "$0")"
base=/Library/Printers/HPNative1217PCLm
queue=HP_M1217_PCLm_600
[ ! -e "$base" ] && [ ! -L "$base" ] || { echo 'Existing driver preserved' >&2; exit 1; }
if /usr/bin/lpstat -p "$queue" >/dev/null 2>&1; then echo 'Existing queue preserved' >&2; exit 1; fi
(cd build && /usr/bin/shasum -a 256 -c SHA256SUMS)
/usr/bin/codesign --verify --strict build/hp-m1217-pclm
/usr/bin/install -d -o root -g wheel -m 755 "$base" "$base/Filters"
/usr/bin/install -o root -g wheel -m 755 build/hp-m1217-pclm "$base/Filters/hp-m1217-pclm"
/usr/bin/install -o root -g wheel -m 644 HP-M1217-PCLm.ppd README.md "$base/"
/usr/bin/install -o root -g wheel -m 755 rollback.sh "$base/rollback.sh"
/usr/bin/cupstestppd "$base/HP-M1217-PCLm.ppd"
/usr/sbin/lpadmin -p "$queue" -E -v "ipp://$ip:631/ipp/print" -P "$base/HP-M1217-PCLm.ppd" -D "HP M1217 PCLm 600" -L "Ethernet" -o printer-is-shared=false -o printer-error-policy=abort-job
/usr/bin/lpstat -p "$queue" -v "$queue"
