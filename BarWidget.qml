import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "harel.vital-signs"
  ipcTarget: moduleName

  readonly property var vitals: root
  property real usedRamBytes: 0
  property real loadAverage: 0
  property real downloadBytesPerSecond: 0
  property real cpuPercent: 0
  property real temperatureCelsius: -1
  property string temperatureLabel: ""
  property var fans: []
  property bool available: false
  property real previousRxBytes: -1
  property real previousNetworkTime: -1
  property real previousCpuIdle: -1
  property real previousCpuTotal: -1
  readonly property string collectorPath: {
    var value = String(Qt.resolvedUrl("collect.sh"))
    if (value.indexOf("file://") === 0) value = value.substring(7)
    return decodeURIComponent(value)
  }
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string statusText: vitals && vitals.available
    ? formatBytes(vitals.usedRamBytes) + "  "
      + Number(vitals.loadAverage).toFixed(2) + "  ↓"
      + formatRate(vitals.downloadBytesPerSecond)
    : "RAM --  LOAD --  ↓--"

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

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
  }

  function refresh() {
    if (!statsProcess.running) statsProcess.running = true
  }

  function applyStats(raw) {
    var nextRx = -1
    var nextIdle = -1
    var nextTotal = -1
    var hottest = -1
    var hottestLabel = ""
    var nextFans = []
    var lines = String(raw || "").trim().split("\n")

    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields[0] === "memory") usedRamBytes = Number(fields[1])
      else if (fields[0] === "load") loadAverage = Number(fields[1])
      else if (fields[0] === "network") nextRx = Number(fields[1])
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
      if (elapsed > 0) downloadBytesPerSecond = (nextRx - previousRxBytes) / elapsed
    }
    if (nextRx >= 0) {
      previousRxBytes = nextRx
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

  function fanSummary() {
    if (!vitals || !vitals.fans || vitals.fans.length === 0)
      return "Not reported"
    var values = []
    for (var i = 0; i < vitals.fans.length; i++)
      values.push(vitals.fans[i].label + "  " + Math.round(vitals.fans[i].rpm) + " RPM")
    return values.join(" · ")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: statsProcess
    command: ["bash", root.collectorPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        console.log("vital-signs collector bytes=" + String(text).length)
        root.applyStats(text)
      }
    }
    stderr: StdioCollector { id: statsError; waitForEnd: true }
    onExited: function(exitCode) {
      console.log("vital-signs collector exit=" + exitCode
        + " error=" + statsError.text)
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
    tooltipText: "Used RAM · 1-minute load · download speed"
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
          text: "HARDWARE"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        MetricRow {
          label: "CPU usage"
          value: root.vitals ? Math.round(root.vitals.cpuPercent) + "%" : "--"
        }

        MetricRow {
          label: root.vitals && root.vitals.temperatureLabel !== ""
            ? root.vitals.temperatureLabel : "Temperature"
          value: root.vitals && root.vitals.temperatureCelsius >= 0
            ? Number(root.vitals.temperatureCelsius).toFixed(1) + "°C"
            : "Not reported"
        }

        MetricRow {
          label: "Fan speed"
          value: root.fanSummary()
          multiline: true
        }
      }
    }
  }

  component MetricRow: Item {
    id: metric
    property string label: ""
    property string value: ""
    property bool multiline: false

    width: parent ? parent.width : implicitWidth
    implicitHeight: row.implicitHeight + Style.space(18)

    RowLayout {
      id: row
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.space(16)

      Text {
        text: metric.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignTop
      }

      Text {
        text: metric.value
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignRight
        wrapMode: metric.multiline ? Text.WordWrap : Text.NoWrap
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
      }
    }
  }
}
