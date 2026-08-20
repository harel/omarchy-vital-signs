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
  readonly property string collectorPath: {
    var value = String(Qt.resolvedUrl("collect.sh"))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value)
  }
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var defaultVisibleMetrics: ["ram", "load1", "download"]
  readonly property var defaultIconMetrics: [
    "ram", "load1", "load5", "load15", "download", "upload", "cpu",
    "temperature", "fan", "battery"
  ]
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
  readonly property var visibleMetricIds: {
    var configured = setting("visibleMetrics", defaultVisibleMetrics)
    return Array.isArray(configured) ? configured : defaultVisibleMetrics
  }
  readonly property var iconMetricIds: {
    var configured = setting("iconMetrics", defaultIconMetrics)
    return Array.isArray(configured) ? configured : defaultIconMetrics
  }
  readonly property int refreshSeconds: {
    var value = Number(setting("refreshSeconds", 2))
    return [1, 2, 5, 10].indexOf(value) !== -1 ? value : 2
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

  function iconEnabled(id) {
    return iconMetricIds.indexOf(id) !== -1
  }

  function metricIcon(id) {
    if (!iconEnabled(id)) return ""
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
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
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

  function toggleMetricIcon(id) {
    var next = iconMetricIds.slice()
    var index = next.indexOf(id)
    if (index === -1) next.push(id)
    else next.splice(index, 1)
    persistSettings({ iconMetrics: next })
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
    contentWidth: popup.fittedContentWidth(Style.space(root.page === "settings" ? 520 : 360))
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
          title: root.page === "settings" ? "Vital Signs Settings" : "Vital Signs"
          meta: root.page === "settings" ? "Bar appearance and updates" : "Live system health"
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
          height: settingsButton.implicitHeight + Style.space(4)

          PanelActionButton {
            id: settingsButton
            anchors.right: parent.right
            iconText: ""
            tooltipText: "Settings"
            foreground: root.foreground
            fontFamily: root.fontFamily
            focusable: true
            onClicked: root.showSettings()
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

          PanelSectionHeader {
            text: "METRIC ICONS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Grid {
            width: parent.width
            columns: 2
            spacing: Style.space(5)

            Repeater {
              model: root.metricCatalog
              Toggle {
                required property var modelData
                width: (parent.width - parent.spacing) / 2
                label: modelData.label
                checked: root.iconEnabled(modelData.id)
                foreground: root.foreground
                accent: root.bar ? root.bar.urgent : Color.accent
                fontFamily: root.fontFamily
                onClicked: root.toggleMetricIcon(modelData.id)
              }
            }
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
    }
  }
}
