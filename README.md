# Vital Signs

An Omarchy 4 shell plugin that displays selectable live system metrics in the
bar. Click the status line to choose metrics; use the settings page to control
the refresh rate, bar alignment, empty-value visibility, and per-metric icons.

## Install

```bash
omarchy plugin add /home/harel/Work/vital-signs --enable
```

For local development, symlink the repository into
`~/.config/omarchy/plugins/harel.vital-signs` and rescan the shell plugins.

## Notes

- Network speed is the combined receive rate for all non-loopback interfaces.
- Battery percentage is read from the first battery exposed in Linux sysfs.
- Temperature and fan availability depend on what the kernel exposes through
  `/sys/class/hwmon`; unsupported hardware is shown as “Not reported”.
- All metrics are read locally without root privileges.
