# Vital Signs

An Omarchy 4 shell plugin that displays selectable live system metrics in the
bar. Click the status line to choose metrics; use the settings page to control
the refresh rate, bar alignment, empty-value visibility, and metric icons.
The Advanced page lists top CPU and RAM processes with confirmed termination
actions, plus a separately confirmed privileged kernel OOM trigger.

## Requirements

- Omarchy 4 with `omarchy-shell`
- A Linux system exposing metrics through `/proc` and `/sys`

## Installation

Install and enable the plugin directly from GitHub:

```bash
omarchy plugin add https://github.com/harel/omarchy-vital-signs.git --enable
```

The command asks for confirmation because Omarchy plugins run inside the
long-lived shell process. After installation, **Vital Signs** appears in the
bar's right section by default.

To update an existing installation:

```bash
omarchy plugin update harel.vital-signs
```

To remove it:

```bash
omarchy plugin remove harel.vital-signs
```

## Local development

Clone the repository anywhere, then symlink it into Omarchy's user plugin
directory:

```bash
git clone https://github.com/harel/omarchy-vital-signs.git
cd omarchy-vital-signs
mkdir -p "$HOME/.config/omarchy/plugins"
ln -s "$PWD" "$HOME/.config/omarchy/plugins/harel.vital-signs"
omarchy-shell shell rescanPlugins
omarchy plugin enable harel.vital-signs
```

Changes under the linked directory are reloaded automatically. If a new file
is not detected, run `omarchy-shell shell rescanPlugins` again.

## Notes

- Network speed is the combined receive rate for all non-loopback interfaces.
- Battery percentage is read from the first battery exposed in Linux sysfs.
- Temperature and fan availability depend on what the kernel exposes through
  `/sys/class/hwmon`; unsupported hardware is shown as “Not reported”.
- All metrics are read locally without root privileges.
- Process termination and the kernel OOM trigger use `pkexec`; both require an
  in-panel confirmation before the system authorization prompt appears.
