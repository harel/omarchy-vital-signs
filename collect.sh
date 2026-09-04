#!/usr/bin/env bash
set -u

if [[ "${1:-}" == "--processes" ]]; then
  cpu_mode=${2:-delta}
  # Fields 2-9 are the non-guest CPU counters. guest/guest_nice are already
  # included in user/nice, so including them again would inflate the divisor.
  cpu_total=$(awk '/^cpu / { for (i = 2; i <= 9; i++) total += $i; print total; exit }' /proc/stat)
  cpu_count=$(getconf _NPROCESSORS_ONLN)
  memory_total_kib=$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)
  current_uid=$(id -u)
  printf 'process_snapshot\t%s\t%s\t%s\n' "$cpu_total" "$cpu_count" "$memory_total_kib"

  if [[ "$cpu_mode" == "ps" ]]; then
    while read -r pid ppid user cpu_percent rss_kib name; do
      if [[ "$pid" == "$$" || "$ppid" == "$$" ]]; then
        continue
      fi
      stat_file="/proc/$pid/stat"
      [[ -r "$stat_file" ]] || continue
      stat_line=$(<"$stat_file")
      stat_fields=${stat_line##*) }
      read -r -a fields <<< "$stat_fields"
      [[ ${#fields[@]} -ge 20 ]] || continue
      start_ticks=${fields[19]}
      printf 'process_ps\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$pid" "$user" "$cpu_percent" "$start_ticks" "$rss_kib" "$name"
    done < <(ps --user "$current_uid" -o pid=,ppid=,user=,pcpu=,rss=,comm=)
    exit 0
  fi

  while read -r pid ppid user rss_kib name; do
    # `ps` and this collector shell are sampling machinery, not workload.
    if [[ "$pid" == "$$" || "$ppid" == "$$" ]]; then
      continue
    fi

    stat_file="/proc/$pid/stat"
    [[ -r "$stat_file" ]] || continue
    stat_line=$(<"$stat_file")
    stat_fields=${stat_line##*) }
    read -r -a fields <<< "$stat_fields"
    [[ ${#fields[@]} -ge 20 ]] || continue

    cpu_ticks=$((fields[11] + fields[12]))
    start_ticks=${fields[19]}
    printf 'process\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$pid" "$user" "$cpu_ticks" "$start_ticks" "$rss_kib" "$name"
  done < <(ps --user "$current_uid" -o pid=,ppid=,user=,rss=,comm=)
  exit 0
fi

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
