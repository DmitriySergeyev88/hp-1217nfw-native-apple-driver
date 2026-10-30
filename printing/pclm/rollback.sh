#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as administrator' >&2; exit 1; }
queue=HP_M1217_PCLm_600
base=/Library/Printers/HPNative1217PCLm
jobs=$(/usr/bin/lpstat -W not-completed -o "$queue")
[ -z "$jobs" ] || { echo 'Queue has jobs; rollback stopped' >&2; exit 1; }
/usr/sbin/lpadmin -x "$queue"
if [ -d "$base" ] && [ ! -L "$base" ]; then
 /bin/mv "$base" "$base.disabled-$(date +%Y%m%d-%H%M%S)"
fi
