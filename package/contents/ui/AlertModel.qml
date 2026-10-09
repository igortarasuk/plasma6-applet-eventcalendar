import QtQuick 2.0

import "./lib/Requests.js" as Requests
import "./ukraine/UkraineAlarm.js" as UkraineAlarm

// Polls the air raid alert level of a single region of Ukraine.
Item {
	id: alertModel

	readonly property bool alertsEnabled: plasmoid.configuration.alertEnabled
	readonly property string regionId: "" + plasmoid.configuration.alertRegionId
	readonly property int pollInterval: Math.max(10, Number(plasmoid.configuration.alertPollInterval || 30)) * 1000
	// Never keep showing "no alert" once we can no longer confirm it.
	readonly property int staleAfter: Math.max(120000, pollInterval * 3)

	// "" (unknown), "none", "yellow" or "red"
	property string level: ""
	property string reason: ""
	property var since: null
	property double lastSuccessAt: 0
	property string lastNotifiedLevel: ""

	readonly property color levelColor: {
		if (level === "red") {
			return "#e74c3c"
		} else if (level === "yellow") {
			return "#f1c40f"
		} else if (level === "none") {
			return "#2ecc71"
		} else {
			return "#7f8c8d"
		}
	}
	readonly property string levelText: {
		if (level === "red") {
			return reason || i18n("Red level: missile threat")
		} else if (level === "yellow") {
			return reason || i18n("Yellow level: elevated threat")
		} else if (level === "none") {
			return i18n("No alert")
		} else {
			return i18n("Alert level unknown")
		}
	}
	readonly property string statusText: {
		var text = UkraineAlarm.getRegionName(regionId)
		text += (text ? ": " : "") + levelText
		if (since && (level === "red" || level === "yellow")) {
			text += " (" + Qt.formatTime(since, appletConfig.timeFormatShort) + ")"
		}
		return text
	}

	onAlertsEnabledChanged: reset()
	onRegionIdChanged: {
		reset()
		if (alertsEnabled) {
			update()
		}
	}

	Timer {
		id: pollTimer
		interval: alertModel.pollInterval
		repeat: true
		running: alertModel.alertsEnabled
		triggeredOnStart: true
		onTriggered: alertModel.update()
	}

	function reset() {
		level = ""
		reason = ""
		since = null
		lastSuccessAt = 0
		lastNotifiedLevel = ""
	}

	function checkIfStale() {
		if (level && Date.now() - lastSuccessAt > staleAfter) {
			logger.debug('alertModel: level is stale')
			level = ""
			reason = ""
			since = null
		}
	}

	function update() {
		if (!networkMonitor.isConnected) {
			checkIfStale()
			return
		}
		var requestedRegionId = regionId
		Requests.getJSON({
			url: UkraineAlarm.alertsUrl(requestedRegionId),
		}, function(err, data, xhr) {
			if (requestedRegionId !== alertModel.regionId || !alertModel.alertsEnabled) {
				return
			}
			var alerts = err ? null : UkraineAlarm.parseAlerts(data, requestedRegionId)
			if (!alerts) {
				logger.debug('alertModel.update.err', err, xhr && xhr.status)
				alertModel.checkIfStale()
				return
			}
			alertModel.lastSuccessAt = Date.now()
			alertModel.reason = alerts.reason
			alertModel.since = alerts.since ? new Date(alerts.since) : null
			alertModel.level = alerts.level
			alertModel.notifyLevelChange()
		})
	}

	function notifyLevelChange() {
		var previousLevel = lastNotifiedLevel
		lastNotifiedLevel = level
		// Don't notify about the level we started with.
		if (!previousLevel || previousLevel === level || !plasmoid.configuration.alertNotify) {
			return
		}
		var summary
		var icon = "dialog-warning"
		if (level === "red") {
			summary = i18n("Air raid alert: red level")
			icon = "dialog-error"
		} else if (level === "yellow") {
			summary = i18n("Air raid alert: yellow level")
		} else {
			summary = i18n("Air raid alert is over")
			icon = "dialog-positive"
		}
		notificationManager.notify({
			appName: i18n("Event Calendar"),
			appIcon: icon,
			summary: summary,
			body: statusText,
		})
	}
}
