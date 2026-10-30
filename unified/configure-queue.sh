#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || exit 1
[ "$#" -eq 2 ] || exit 1
ip=$1
uuid=$2
case "$ip" in ''|*[!0-9.]*|.*|*.|*..*) exit 1;; esac
oldIFS=$IFS;IFS=.;set -- $ip;IFS=$oldIFS
[ "$#" -eq 4 ] || exit 1
for octet in "$@"; do [ "${#octet}" -le 3 ] && [ "$octet" -le 255 ] || exit 1;done
case "$uuid" in *[!0-9a-fA-F-]*) exit 1;; esac
[ -z "$uuid" ] || [ "${#uuid}" -eq 36 ] || exit 1
base=/Library/Printers/HPNative1217PCLm
queue=HP_M1217_PCLm_600
if /usr/bin/lpstat -p "$queue" >/dev/null 2>&1; then
 /usr/bin/grep -Fq "$base/Filters/hp-m1217-pclm" "/etc/cups/ppd/$queue.ppd" || { echo 'Unrelated queue preserved';exit 1; }
 jobs=$(/usr/bin/lpstat -W not-completed -o "$queue")
 [ -z "$jobs" ] || { echo 'Active jobs exist; finish or cancel them first';exit 1; }
fi
staged=$(/usr/bin/mktemp "$base/linked.XXXXXX")
trap '/bin/rm -f "$staged"' EXIT HUP INT TERM
/bin/cat "$base/HP-M1217-PCLm.ppd" > "$staged"
if [ -n "$uuid" ]; then /usr/bin/printf '\n*APScannerUUID: "%s"\n' "$uuid" >> "$staged";fi
/usr/sbin/lpadmin -p "$queue" -E -v "ipp://$ip:631/ipp/print" -P "$staged" -D 'HP M1217 PCLm 600' -o printer-is-shared=false -o printer-error-policy=abort-job
