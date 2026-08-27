import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "harel.vital-signs"
  ipcTarget: moduleName

  property real usedRamBytes: 0
  property real loadAverage: 0
  property real loadAverage5: 0
  property real loadAverage15: 0
  property real downloadBytesPerSecond: 0
  property real uploadBytesPerSecond: 0
  property real cpuPercent: 0
  property real batteryPercent: -1
  property real temperatureCelsius: -1
  property string temperatureLabel: ""
  property var fans: []
  property bool available: false
  property real previousRxBytes: -1
  property real previousTxBytes: -1
  property real previousNetworkTime: -1
  property real previousCpuIdle: -1
  property real previousCpuTotal: -1
  property string page: "metrics"
  property var topCpuProcesses: []
  property var topRamProcesses: []
  property string pendingAction: ""
  property var pendingProcess: null
  readonly property string collectorPath: {
    var value = String(Qt.resolvedUrl("collect.sh"))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value)
  }
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var defaultVisibleMetrics: ["ram", "load1", "download"]
  readonly property var metricCatalog: [
    { id: "ram", label: "Used RAM", icon: "󰘚" },
    { id: "load1", label: "1-minute load", icon: "󰓅" },
    { id: "load5", label: "5-minute load", icon: "󰓅" },
    { id: "load15", label: "15-minute load", icon: "󰓅" },
    { id: "download", label: "Download speed", icon: "↓" },
    { id: "upload", label: "Upload speed", icon: "↑" },
    { id: "cpu", label: "CPU usage", icon: "󰍛" },
    { id: "temperature", label: "Temperature", icon: "" },
    { id: "fan", label: "Fan speed", icon: "󰈐" },
    { id: "battery", label: "Battery", icon: "" }
  ]
  // Settings that arrive from the shell's config store are QVariantList
  // proxies rather than real JS arrays, so Array.isArray() rejects them and
  // the widget silently falls back to the defaults. That happens on every
  // widget rebuild -- lock/unlock on resume, a monitor coming back, a plugin
  // rescan -- so read the value as an array-like and copy it out instead.
  readonly property var visibleMetricIds: {
    var configured = setting("visibleMetrics", null)
    if (configured === null || typeof configured.length !== "number")
      return defaultVisibleMetrics
    var ids = []
    for (var i = 0; i < configured.length; i++) ids.push(String(configured[i]))
    return ids
  }
  readonly property bool showIcons: setting("showIcons", true) === true
  readonly property int refreshSeconds: {
    var value = Number(setting("refreshSeconds", 5))
    return [1, 2, 5, 10].indexOf(value) !== -1 ? value : 5
  }
  readonly property string alignment: String(setting("alignment", "right"))
  readonly property bool hideZeroValues: setting("hideZeroValues", false) === true
  readonly property string statusText: buildStatusText()

  function formatBytes(bytes) {
    var value = Number(bytes)
    if (!isFinite(value) || value < 0) return "--"
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var index = 0
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024
      index++
    }
    var digits = index >= 3 ? 1 : 0
    return value.toFixed(digits) + units[index]
  }

  function formatRate(bytes) {
    return formatBytes(bytes) + "/s"
  }

  function metricSelected(id) {
    return visibleMetricIds.indexOf(id) !== -1
  }

  function metricIcon(id) {
    if (!showIcons) return ""
    for (var i = 0; i < metricCatalog.length; i++)
      if (metricCatalog[i].id === id) return metricCatalog[i].icon + " "
    return ""
  }

  function maximumFanRpm() {
    var maximum = -1
    for (var i = 0; i < fans.length; i++)
      maximum = Math.max(maximum, Number(fans[i].rpm))
    return maximum
  }

  function metricValue(id, includeLabel) {
    var prefix = metricIcon(id)
    var value = "--"
    if (id === "ram") {
      value = available ? formatBytes(usedRamBytes) : "--"
    } else if (id === "load1") {
      prefix += "1m "
      value = available ? Number(loadAverage).toFixed(2) : "--"
    } else if (id === "load5") {
      prefix += "5m "
      value = available ? Number(loadAverage5).toFixed(2) : "--"
    } else if (id === "load15") {
      prefix += "15m "
      value = available ? Number(loadAverage15).toFixed(2) : "--"
    } else if (id === "download") {
      value = available ? formatRate(downloadBytesPerSecond) : "--"
    } else if (id === "upload") {
      value = available ? formatRate(uploadBytesPerSecond) : "--"
    } else if (id === "cpu") {
      value = available ? Math.round(cpuPercent) + "%" : "--"
    } else if (id === "temperature") {
      value = temperatureCelsius >= 0
        ? Number(temperatureCelsius).toFixed(1) + "°C" : "--"
    } else if (id === "fan") {
      var rpm = maximumFanRpm()
      value = rpm >= 0 ? Math.round(rpm) + "rpm" : "--"
    } else if (id === "battery") {
      value = batteryPercent >= 0 ? Math.round(batteryPercent) + "%" : "--"
    }
    return (includeLabel ? prefix : "") + value
  }

  function metricNumericValue(id) {
    if (id === "ram") return available ? usedRamBytes : -1
    if (id === "load1") return available ? loadAverage : -1
    if (id === "load5") return available ? loadAverage5 : -1
    if (id === "load15") return available ? loadAverage15 : -1
    if (id === "download") return available ? downloadBytesPerSecond : -1
    if (id === "upload") return available ? uploadBytesPerSecond : -1
    if (id === "cpu") return available ? cpuPercent : -1
    if (id === "temperature") return temperatureCelsius
    if (id === "fan") return maximumFanRpm()
    if (id === "battery") return batteryPercent
    return -1
  }

  function metricHidden(id) {
    return hideZeroValues && metricNumericValue(id) <= 0
  }

  function buildStatusText() {
    var values = []
    for (var i = 0; i < visibleMetricIds.length; i++) {
      var id = String(visibleMetricIds[i])
      for (var j = 0; j < metricCatalog.length; j++) {
        if (metricCatalog[j].id === id) {
          if (!metricHidden(id)) values.push(metricValue(id, true))
          break
        }
      }
    }
    return values.length > 0 ? values.join("  ") : "Vital Signs"
  }

  function persistSettings(values) {
    var entry = { id: moduleName }
    for (var key in settings)
      if (key !== "id" && key !== "iconMetrics") entry[key] = settings[key]
    for (var name in values) entry[name] = values[name]
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  function toggleMetric(id) {
    var next = visibleMetricIds.slice()
    var index = next.indexOf(id)
    if (index === -1) next.push(id)
    else next.splice(index, 1)
    persistSettings({ visibleMetrics: next })
  }

  function setRefreshSeconds(value) {
    persistSettings({ refreshSeconds: value })
  }

  function setAlignment(section) {
    if (["left", "center", "right"].indexOf(section) === -1) return
    persistSettings({ alignment: section })
    root.close()
    Quickshell.execDetached([
      "omarchy", "bar", "move", moduleName, "--section", section
    ])
  }

  function showSettings() {
    page = "settings"
  }

  function showMetrics() {
    page = "metrics"
  }

  function showAdvanced() {
    page = "advanced"
  }

  function requestProcessKill(process) {
    if (!process) return
    pendingAction = "kill"
    pendingProcess = process
    confirmDialog.message = "Terminate " + process.name + " (PID "
      + process.pid + ") with SIGTERM?"
    confirmDialog.confirmText = "Terminate"
    confirmDialog.selectedIndex = 0
    confirmDialog.opened = true
  }

  function requestOomTrigger() {
    pendingAction = "oom"
    pendingProcess = null
    confirmDialog.message = "Trigger the kernel OOM killer now? This is a nuclear option: the kernel will choose and kill a memory-consuming process, which may cause data loss or destabilize the session."
    confirmDialog.confirmText = "Trigger OOM"
    confirmDialog.selectedIndex = 0
    confirmDialog.opened = true
  }

  function runConfirmedAction() {
    confirmDialog.opened = false
    if (pendingAction === "kill" && pendingProcess) {
      var process = pendingProcess
      Quickshell.execDetached([
        "pkexec", "sh", "-c",
        "pid=\"$1\"; expected=\"$2\"; "
          + "[ -r \"/proc/$pid/comm\" ] || exit 1; "
          + "current=$(cat \"/proc/$pid/comm\"); "
          + "[ \"$current\" = \"$expected\" ] || exit 2; "
          + "kill -TERM -- \"$pid\"",
        "vital-signs-kill", String(process.pid), String(process.name)
      ])
    } else if (pendingAction === "oom") {
      Quickshell.execDetached([
        "pkexec", "sh", "-c", "printf f > /proc/sysrq-trigger"
      ])
    }
    pendingAction = ""
    pendingProcess = null
  }

  function cancelConfirmedAction() {
    confirmDialog.opened = false
    pendingAction = ""
    pendingProcess = null
  }

  onOpenedChanged: if (!opened) page = "metrics"

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
  }

  function refresh() {
    if (!statsProcess.running) statsProcess.running = true
  }

  function applyStats(raw) {
    var nextRx = -1
    var nextTx = -1
    var nextIdle = -1
    var nextTotal = -1
    var hottest = -1
    var hottestLabel = ""
    var nextFans = []
    var nextTopCpu = []
    var nextTopRam = []
    var lines = String(raw || "").trim().split("\n")

    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields[0] === "memory") usedRamBytes = Number(fields[1])
      else if (fields[0] === "load") {
        loadAverage = Number(fields[1])
        loadAverage5 = Number(fields[2])
        loadAverage15 = Number(fields[3])
      } else if (fields[0] === "network") {
        nextRx = Number(fields[1])
        nextTx = Number(fields[2])
      } else if (fields[0] === "battery") {
        batteryPercent = Number(fields[1])
      }
      else if (fields[0] === "cpu") {
        nextIdle = Number(fields[1])
        nextTotal = Number(fields[2])
      } else if (fields[0] === "temp") {
        var temperature = Number(fields[2]) / 1000
        if (isFinite(temperature) && temperature > 0 && temperature > hottest) {
          hottest = temperature
          hottestLabel = fields[1] || "Temperature"
        }
      } else if (fields[0] === "fan") {
        var rpm = Number(fields[2])
        if (isFinite(rpm)) nextFans.push({ label: fields[1], rpm: rpm })
      } else if (fields[0] === "process_cpu" || fields[0] === "process_ram") {
        var process = {
          pid: Number(fields[1]),
          user: fields[2] || "",
          cpu: Number(fields[3]),
          memory: Number(fields[4]),
          name: fields[5] || "unknown"
        }
        if (fields[0] === "process_cpu") nextTopCpu.push(process)
        else nextTopRam.push(process)
      }
    }

    var now = Date.now()
    if (previousRxBytes >= 0 && nextRx >= previousRxBytes && previousNetworkTime > 0) {
      var elapsed = (now - previousNetworkTime) / 1000
      if (elapsed > 0) {
        downloadBytesPerSecond = (nextRx - previousRxBytes) / elapsed
        if (previousTxBytes >= 0 && nextTx >= previousTxBytes)
          uploadBytesPerSecond = (nextTx - previousTxBytes) / elapsed
      }
    }
    if (nextRx >= 0) {
      previousRxBytes = nextRx
      previousTxBytes = nextTx
      previousNetworkTime = now
    }
    if (previousCpuTotal >= 0 && nextTotal > previousCpuTotal) {
      var totalDelta = nextTotal - previousCpuTotal
      var idleDelta = nextIdle - previousCpuIdle
      cpuPercent = clamp((1 - idleDelta / totalDelta) * 100, 0, 100)
    }
    if (nextIdle >= 0 && nextTotal >= 0) {
      previousCpuIdle = nextIdle
      previousCpuTotal = nextTotal
    }

    temperatureCelsius = hottest
    temperatureLabel = hottestLabel
    fans = nextFans
    topCpuProcesses = nextTopCpu
    topRamProcesses = nextTopRam
    available = isFinite(usedRamBytes) && isFinite(loadAverage)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statsProcess
    command: ["bash", root.collectorPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStats(text)
    }
  }

  Timer {
    interval: root.refreshSeconds * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.statusText
    fontFamily: root.fontFamily
    tooltipText: "Click to choose metrics and view hardware details"
    horizontalMargin: 10
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(root.page === "advanced" ? 520 : 360))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: root.page === "settings" ? "Vital Signs Settings"
            : (root.page === "advanced" ? "Vital Signs Advanced" : "Vital Signs")
          meta: root.page === "settings" ? "Bar appearance and updates"
            : (root.page === "advanced" ? "Processes and emergency memory controls" : "Live system health")
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Column {
          visible: root.page === "metrics"
          width: parent.width
          spacing: Style.space(10)

        PanelSectionHeader {
          text: "HEADER METRICS"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(5)

          Repeater {
            model: root.metricCatalog

            Toggle {
              required property var modelData
              width: parent.width
              label: modelData.label
              description: root.metricValue(modelData.id, false)
              foreground: root.foreground
              accent: root.bar ? root.bar.urgent : Color.accent
              fontFamily: root.fontFamily
              checked: root.metricSelected(modelData.id)
              onClicked: root.toggleMetric(modelData.id)
            }
          }
        }

        Item {
          width: parent.width
          height: footerButtons.implicitHeight + Style.space(4)

          Row {
            id: footerButtons
            anchors.right: parent.right
            spacing: Style.space(6)

            PanelActionButton {
              iconText: ""
              tooltipText: "Advanced"
              foreground: root.foreground
              fontFamily: root.fontFamily
              focusable: true
              onClicked: root.showAdvanced()
            }

          PanelActionButton {
            id: settingsButton
            iconText: ""
            tooltipText: "Settings"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            onClicked: root.showSettings()
          }
          }
        }
        }

        Column {
          visible: root.page === "settings"
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "REFRESH RATE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: [1, 2, 5, 10]
              Button {
                required property int modelData
                text: modelData + "s"
                selected: root.refreshSeconds === modelData
                foreground: root.foreground
                accent: root.bar ? root.bar.urgent : Color.accent
                fontFamily: root.fontFamily
                onClicked: root.setRefreshSeconds(modelData)
              }
            }
          }

          PanelSectionHeader {
            text: "BAR ALIGNMENT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: ["left", "center", "right"]
              Button {
                required property string modelData
                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                selected: root.alignment === modelData
                foreground: root.foreground
                accent: root.bar ? root.bar.urgent : Color.accent
                fontFamily: root.fontFamily
                onClicked: root.setAlignment(modelData)
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Hide unavailable or zero values"
            description: "Keep empty sensors and idle metrics out of the bar."
            foreground: root.foreground
            accent: root.bar ? root.bar.urgent : Color.accent
            fontFamily: root.fontFamily
            checked: root.hideZeroValues
            onClicked: root.persistSettings({ hideZeroValues: !root.hideZeroValues })
          }

          Toggle {
            width: parent.width
            label: "Show metric icons"
            description: "Display an icon before each measurement in the bar."
            checked: root.showIcons
            foreground: root.foreground
            accent: root.bar ? root.bar.urgent : Color.accent
            fontFamily: root.fontFamily
            onClicked: root.persistSettings({ showIcons: !root.showIcons })
          }

          Button {
            text: "Back"
            iconText: "‹"
            bordered: true
            foreground: root.foreground
            accent: root.bar ? root.bar.urgent : Color.accent
            fontFamily: root.fontFamily
            onClicked: root.showMetrics()
          }
        }

        Column {
          visible: root.page === "advanced"
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "TOP CPU"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.topCpuProcesses
            ProcessRow {
              required property var modelData
              process: modelData
              valueText: Number(modelData.cpu).toFixed(1) + "% CPU"
            }
          }

          PanelSectionHeader {
            text: "TOP RAM"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.topRamProcesses
            ProcessRow {
              required property var modelData
              process: modelData
              valueText: Number(modelData.memory).toFixed(1) + "% RAM"
            }
          }

          Button {
            width: parent.width
            text: "Trigger kernel OOM killer"
            iconText: "󰚌"
            bordered: true
            foreground: root.bar ? root.bar.urgent : Color.urgent
            accent: root.bar ? root.bar.urgent : Color.urgent
            fontFamily: root.fontFamily
            onClicked: root.requestOomTrigger()
          }

          Button {
            text: "Back"
            iconText: "‹"
            bordered: true
            foreground: root.foreground
            accent: root.bar ? root.bar.urgent : Color.accent
            fontFamily: root.fontFamily
            onClicked: root.showMetrics()
          }
        }

      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.cancelConfirmedAction()
        onConfirmed: root.runConfirmedAction()
      }
    }
  }

  component ProcessRow: BorderSurface {
    id: processRow
    required property var process
    property string valueText: ""

    width: parent ? parent.width : implicitWidth
    implicitHeight: Style.space(44)
    color: "transparent"
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
    radius: Style.cornerRadius

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width * 0.48
      text: processRow.process.name + "  ·  " + processRow.process.user
        + "  ·  PID " + processRow.process.pid
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Text {
      anchors.right: killButton.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: processRow.valueText
      color: Qt.darker(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    PanelActionButton {
      id: killButton
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      iconText: "󰅙"
      tooltipText: "Terminate process"
      foreground: root.foreground
      hoverColor: root.bar ? root.bar.urgent : Color.urgent
      fontFamily: root.fontFamily
      onClicked: root.requestProcessKill(processRow.process)
    }
  }
}
