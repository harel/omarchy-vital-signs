#!/usr/bin/env bash
set -u

awk '
  /^MemTotal:/ { total = $2 * 1024 }
  /^MemAvailable:/ { available = $2 * 1024 }
  END { printf "memory\t%.0f\n", total - available }
' /proc/meminfo

awk '{ print "load\t" $1 "\t" $2 "\t" $3 }' /proc/loadavg

awk '
  NR > 2 {
    name = $1
    sub(/:$/, "", name)
    if (name != "lo") {
      rx += $2
      tx += $10
    }
  }
  END { printf "network\t%.0f\t%.0f\n", rx, tx }
' /proc/net/dev

awk '
  /^cpu / {
    idle = $5 + $6
    total = 0
    for (i = 2; i <= NF; i++) total += $i
    printf "cpu\t%.0f\t%.0f\n", idle, total
  }
' /proc/stat

battery=-1
for capacity in /sys/class/power_supply/BAT*/capacity; do
  [[ -r "$capacity" ]] || continue
  value=$(<"$capacity")
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    battery="$value"
    break
  fi
done
printf 'battery\t%s\n' "$battery"

shopt -s nullglob
for input in /sys/class/hwmon/hwmon*/temp*_input; do
  [[ -r "$input" ]] || continue
  value=$(<"$input")
  [[ "$value" =~ ^[0-9]+$ ]] || continue
  label_file="${input%_input}_label"
  label="Temperature"
  [[ -r "$label_file" ]] && label=$(<"$label_file")
  printf 'temp\t%s\t%s\n' "$label" "$value"
done

for input in /sys/class/hwmon/hwmon*/fan*_input; do
  [[ -r "$input" ]] || continue
  value=$(<"$input")
  [[ "$value" =~ ^[0-9]+$ ]] || continue
  label_file="${input%_input}_label"
  label="$(basename "${input%_input}")"
  [[ -r "$label_file" ]] && label=$(<"$label_file")
  printf 'fan\t%s\t%s\n' "$label" "$value"
done
