#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo 'Run as administrator after closing scanner apps';exit 1; }
base=/Library/Printers/HPNative1217PCLm
queue=HP_M1217_PCLm_600
if /usr/bin/lpstat -p "$queue" >/dev/null 2>&1; then
 /usr/bin/grep -Fq "$base/Filters/hp-m1217-pclm" "/etc/cups/ppd/$queue.ppd" || exit 1
 jobs=$(/usr/bin/lpstat -W not-completed -o "$queue");[ -z "$jobs" ] || { echo 'Active print jobs; stopped';exit 1; }
 /usr/sbin/lpadmin -x "$queue"
fi
backup="/Users/Shared/HP-M1217-backup-$(date +%Y%m%d-%H%M%S)"
/bin/mkdir -m 755 "$backup"
for path in '/Applications/HP M1217 Setup.app' '/Applications/HP M1217 Native Scan.app' '/Applications/HP M1217 ICA Discovery.app' '/Library/Image Capture/Devices/HP M1217 Native ICA.app' "$base"; do
 if [ -e "$path" ] && [ ! -L "$path" ]; then /bin/mv "$path" "$backup/";fi
done
echo "Preserved components: $backup. Scan documents and old drivers were not removed."
