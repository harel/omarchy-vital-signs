import QtQuick
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
  property real temperatureCelsius: -1
  property string temperatureLabel: ""
  property var fans: []
  property bool available: false
  property real previousRxBytes: -1
  property real previousTxBytes: -1
  property real previousNetworkTime: -1
  property real previousCpuIdle: -1
  property real previousCpuTotal: -1
  readonly property string collectorPath: {
    var value = String(Qt.resolvedUrl("collect.sh"))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value)
  }
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var defaultVisibleMetrics: ["ram", "load1", "download"]
  readonly property var metricCatalog: [
    { id: "ram", label: "Used RAM" },
    { id: "load1", label: "1-minute load" },
    { id: "load5", label: "5-minute load" },
    { id: "load15", label: "15-minute load" },
    { id: "download", label: "Download speed" },
    { id: "upload", label: "Upload speed" },
    { id: "cpu", label: "CPU usage" },
    { id: "temperature", label: "Temperature" },
    { id: "fan", label: "Fan speed" }
  ]
  readonly property var visibleMetricIds: {
    var configured = setting("visibleMetrics", defaultVisibleMetrics)
    return Array.isArray(configured) ? configured : defaultVisibleMetrics
  }
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

  function maximumFanRpm() {
    var maximum = -1
    for (var i = 0; i < fans.length; i++)
      maximum = Math.max(maximum, Number(fans[i].rpm))
    return maximum
  }

  function metricValue(id, includeLabel) {
    var prefix = ""
    var value = "--"
    if (id === "ram") {
      prefix = "RAM "
      value = available ? formatBytes(usedRamBytes) : "--"
    } else if (id === "load1") {
      prefix = "1m "
      value = available ? Number(loadAverage).toFixed(2) : "--"
    } else if (id === "load5") {
      prefix = "5m "
      value = available ? Number(loadAverage5).toFixed(2) : "--"
    } else if (id === "load15") {
      prefix = "15m "
      value = available ? Number(loadAverage15).toFixed(2) : "--"
    } else if (id === "download") {
      prefix = "↓"
      value = available ? formatRate(downloadBytesPerSecond) : "--"
    } else if (id === "upload") {
      prefix = "↑"
      value = available ? formatRate(uploadBytesPerSecond) : "--"
    } else if (id === "cpu") {
      prefix = "CPU "
      value = available ? Math.round(cpuPercent) + "%" : "--"
    } else if (id === "temperature") {
      prefix = "TEMP "
      value = temperatureCelsius >= 0
        ? Number(temperatureCelsius).toFixed(1) + "°C" : "--"
    } else if (id === "fan") {
      prefix = "FAN "
      var rpm = maximumFanRpm()
      value = rpm >= 0 ? Math.round(rpm) + "rpm" : "--"
    }
    return (includeLabel ? prefix : "") + value
  }

  function buildStatusText() {
    var values = []
    for (var i = 0; i < visibleMetricIds.length; i++) {
      var id = String(visibleMetricIds[i])
      for (var j = 0; j < metricCatalog.length; j++) {
        if (metricCatalog[j].id === id) {
          values.push(metricValue(id, true))
          break
        }
      }
    }
    return values.length > 0 ? values.join("  ") : "Vital Signs"
  }

  function persistVisibleMetrics(values) {
    var entry = { id: moduleName }
    for (var key in settings) if (key !== "id") entry[key] = settings[key]
    entry.visibleMetrics = values
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
  }

  function toggleMetric(id) {
    var next = visibleMetricIds.slice()
    var index = next.indexOf(id)
    if (index === -1) next.push(id)
    else next.splice(index, 1)
    persistVisibleMetrics(next)
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
    interval: 2000
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
    contentWidth: popup.fittedContentWidth(Style.space(360))
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
          title: "Vital Signs"
          meta: "Live system health"
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

      }
    }
  }
}
