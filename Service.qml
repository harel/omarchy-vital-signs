import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
  id: root

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

  function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value))
  }

  function refresh() {
    if (!collector.running) collector.running = true
  }

  function apply(raw) {
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

  property Process collector: Process {
    id: collector
    command: ["bash", root.collectorPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.apply(text)
    }
  }

  property Timer pollTimer: Timer {
    interval: 2000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
