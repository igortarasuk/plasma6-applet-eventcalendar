import QtQuick 2.0

import "LocaleFuncs.js" as LocaleFuncs

QtObject {
	id: shutdownModel

	readonly property int stepSeconds: 30 * 60
	readonly property int warningSeconds: 60
	readonly property string shutdownCommand: 'dbus-send --session --print-reply --dest=org.kde.Shutdown /Shutdown org.kde.Shutdown.logoutAndShutdown || systemctl poweroff'

	property var presets: [
		{ seconds: 15 * 60 },
		{ seconds: 30 * 60 },
		{ seconds: 60 * 60 },
		{ seconds: 90 * 60 },
		{ seconds: 2 * 60 * 60 },
		{ seconds: 3 * 60 * 60 },
	]

	// Milliseconds since epoch. 0 = not scheduled.
	property double shutdownAt: 0
	readonly property bool active: shutdownAt > 0
	property int secondsLeft: 0
	property bool warned: false

	property Timer ticker: Timer {
		interval: 1000
		running: shutdownModel.active
		repeat: true
		onTriggered: shutdownModel.tick()
	}

	// Survive a plasmashell restart.
	Component.onCompleted: {
		var saved = parseFloat(plasmoid.configuration.shutdownAt)
		if (saved > Date.now()) {
			schedule(saved)
		} else if (plasmoid.configuration.shutdownAt) {
			plasmoid.configuration.shutdownAt = ''
		}
	}

	function schedule(timestamp) {
		shutdownModel.warned = false
		shutdownModel.shutdownAt = timestamp
		plasmoid.configuration.shutdownAt = '' + timestamp
		tick()
	}

	function setDelay(nSeconds) {
		schedule(Date.now() + nSeconds * 1000)
	}

	function postpone(nSeconds) {
		var from = active ? shutdownAt : Date.now()
		schedule(from + (nSeconds || stepSeconds) * 1000)
	}

	function cancel() {
		shutdownModel.shutdownAt = 0
		shutdownModel.secondsLeft = 0
		shutdownModel.warned = false
		plasmoid.configuration.shutdownAt = ''
	}

	function tick() {
		if (!active) {
			return
		}
		var now = Date.now()
		var left = Math.ceil((shutdownAt - now) / 1000)
		if (left < -10 || (!warned && left < warningSeconds - 10)) {
			// The clock jumped (eg: resumed from suspend).
			// Never power off without showing the warning first.
			shutdownModel.warned = false
			shutdownModel.shutdownAt = now + warningSeconds * 1000
			plasmoid.configuration.shutdownAt = '' + shutdownModel.shutdownAt
			left = warningSeconds
		}
		shutdownModel.secondsLeft = Math.max(0, left)

		if (left <= 0) {
			shutdown()
		} else if (!warned && left <= warningSeconds) {
			shutdownModel.warned = true
			createNotification()
		}
	}

	function shutdown() {
		logger.log('ShutdownModel.shutdown')
		cancel()
		executable.exec(shutdownCommand)
	}

	function createNotification() {
		var args = {
			appName: i18n("Shutdown timer"),
			appIcon: "system-shutdown",
			summary: i18n("Shutdown timer"),
			body: i18n("The computer will shut down in %1", LocaleFuncs.durationShortFormat(secondsLeft)),
			expireTimeout: warningSeconds * 1000,
		}
		if (plasmoid.configuration.timerSfxEnabled) {
			args.soundFile = plasmoid.configuration.timerSfxFilepath
		}
		args.actions = [
			'postpone' + ',' + i18n("Postpone by %1", LocaleFuncs.durationShortFormat(stepSeconds)),
			'cancel' + ',' + i18n("Cancel shutdown"),
		]

		// Ignore the buttons of a stale notification.
		var warnedFor = shutdownAt
		notificationManager.notify(args, function(actionId) {
			if (shutdownModel.shutdownAt !== warnedFor) {
				return
			}
			if (actionId === 'postpone') {
				postpone()
			} else if (actionId === 'cancel') {
				cancel()
			}
		})
	}
}
