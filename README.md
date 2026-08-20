# Vital Signs

An Omarchy 4 shell plugin that displays used RAM, one-minute load average, and
live network download speed in the bar. Click the status line for CPU usage,
the hottest readable temperature sensor, and fan speeds exposed by Linux hwmon.

## Install

```bash
omarchy plugin add /home/harel/Work/vital-signs --enable
```

For local development, symlink the repository into
`~/.config/omarchy/plugins/harel.vital-signs` and rescan the shell plugins.

## Notes

- Network speed is the combined receive rate for all non-loopback interfaces.
- Temperature and fan availability depend on what the kernel exposes through
  `/sys/class/hwmon`; unsupported hardware is shown as “Not reported”.
- All metrics are read locally without root privileges.
