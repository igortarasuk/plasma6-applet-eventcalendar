import QtQuick 2.0

import "../lib/Requests.js" as Requests
import "../ukraine/Yasno.js" as Yasno

// Shows the planned power outages of a Yasno group as read-only events.
CalendarManager {
	id: yasnoOutageManager

	calendarManagerId: "yasno"
	readonly property string outageCalendarId: "yasno_outages"
	readonly property string outageColor: "#ff8f00"

	readonly property string group: ("" + plasmoid.configuration.outageGroup).trim()
	readonly property int streetId: plasmoid.configuration.outageStreetId
	readonly property int houseId: plasmoid.configuration.outageHouseId
	readonly property bool hasAddress: streetId > 0 && houseId > 0
	readonly property bool outagesEnabled: plasmoid.configuration.outageEnabled && (hasAddress || Yasno.isGroupValid(group))

	// Keep showing the last known schedule when a refresh fails.
	property var lastSchedule: null
	property string lastScheduleKey: ""
	// { "2026-10-09": "emergency" } as of the last successful refresh.
	property var lastDayKinds: ({})

	function createEvents(schedule) {
		var items = []
		if (!schedule) {
			return items
		}
		var description = i18n("Group %1", group)
		schedule.outages.forEach(function(outage) {
			if (outage.end <= dateMin.getTime() || dateMax.getTime() <= outage.start) {
				return
			}
			items.push({
				"id": outageCalendarId + "_" + outage.start + "_" + outage.end,
				"htmlLink": Yasno.websiteUrl,
				"summary": outage.definite ? i18n("Power outage") : i18n("Possible power outage"),
				"description": description,
				"start": { "dateTime": new Date(outage.start).toISOString() },
				"end": { "dateTime": new Date(outage.end).toISOString() },
				"backgroundColor": outageColor,
				"canEdit": false,
				"isPowerOutage": true,
				"outageDefinite": outage.definite,
			})
		})
		schedule.emergencyDays.forEach(function(day) {
			items.push({
				"id": outageCalendarId + "_emergency_" + day.start,
				"htmlLink": Yasno.websiteUrl,
				"summary": i18n("Emergency power outages"),
				"description": description + "\n" + i18n("The schedule doesn't apply."),
				"start": { "date": day.start },
				"end": { "date": day.end },
				"backgroundColor": outageColor,
				"canEdit": false,
			})
		})
		schedule.unknownDays.forEach(function(day) {
			items.push({
				"id": outageCalendarId + "_unknown_" + day.start,
				"htmlLink": Yasno.websiteUrl,
				"summary": i18n("Power outage schedule unavailable"),
				"description": description + "\n" + i18n("Unknown schedule status: %1", day.status),
				"start": { "date": day.start },
				"end": { "date": day.end },
				"backgroundColor": outageColor,
				"canEdit": false,
			})
		})
		return items
	}

	function formatDay(dateString) {
		var date = new Date(dateString + ' 00:00:00')
		return date.toLocaleDateString(Qt.locale(), i18nc("power outage notification date format", "MMMM d"))
	}

	function notifyDayKindChanges(dayKinds) {
		var previousDayKinds = lastDayKinds
		lastDayKinds = dayKinds
		if (!plasmoid.configuration.outageNotify) {
			return
		}
		for (var dateString in dayKinds) {
			var kind = dayKinds[dateString]
			var previousKind = previousDayKinds[dateString]
			var summary = ""
			var icon = "dialog-warning"
			if (kind === 'emergency' && previousKind !== 'emergency') {
				summary = i18n("Emergency power outages")
			} else if (kind === 'schedule' && previousKind === 'emergency') {
				summary = i18n("Power outages are back on schedule")
				icon = "dialog-positive"
			} else {
				continue
			}
			var body = formatDay(dateString) + ", " + i18n("Group %1", group)
			if (kind === 'emergency') {
				body += "<br />" + i18n("The schedule doesn't apply.")
			}
			notificationManager.notify({
				appName: i18n("Event Calendar"),
				appIcon: icon,
				summary: summary,
				body: body,
			})
		}
	}

	// Yasno moves houses between groups from time to time, so with a saved address
	// the group is looked up again before every schedule refresh. A failed lookup
	// keeps the last known group.
	function refreshGroup(callback) {
		var regionId = plasmoid.configuration.outageRegionId
		var dsoId = plasmoid.configuration.outageDsoId
		yasnoOutageManager.asyncRequests += 1
		Requests.getJSON({
			url: Yasno.groupUrl(regionId, dsoId, streetId, houseId),
		}, function(err, data, xhr) {
			var newGroup = err ? "" : Yasno.formatGroup(data)
			if (err) {
				logger.log('yasno.refreshGroup.err', err, xhr && xhr.status)
			} else if (!Yasno.isGroupValid(newGroup)) {
				logger.log('yasno.refreshGroup: no group for address', JSON.stringify(data))
			} else if (newGroup !== yasnoOutageManager.group) {
				var oldGroup = yasnoOutageManager.group
				logger.log('yasno: group changed', oldGroup, '->', newGroup)
				plasmoid.configuration.outageGroup = newGroup
				if (oldGroup && plasmoid.configuration.outageNotify) {
					notificationManager.notify({
						appName: i18n("Event Calendar"),
						appIcon: "dialog-information",
						summary: i18n("Power outage group changed"),
						body: i18n("%1: group %2 → %3", plasmoid.configuration.outageAddress, oldGroup, newGroup),
					})
				}
			}
			callback()
			yasnoOutageManager.asyncRequestsDone += 1
		})
	}

	onFetchAllCalendars: {
		if (!outagesEnabled) {
			return
		}
		if (hasAddress) {
			refreshGroup(fetchSchedule)
		} else {
			fetchSchedule()
		}
	}

	function fetchSchedule() {
		if (!Yasno.isGroupValid(group)) {
			return
		}
		var regionId = plasmoid.configuration.outageRegionId
		var dsoId = plasmoid.configuration.outageDsoId
		var scheduleKey = [regionId, dsoId, group].join('/')
		if (scheduleKey !== lastScheduleKey) {
			lastSchedule = null
			lastDayKinds = {}
			lastScheduleKey = scheduleKey
		}

		logger.debug('yasno.fetchAllCalendars', scheduleKey)
		yasnoOutageManager.asyncRequests += 1
		Requests.getJSON({
			url: Yasno.plannedOutagesUrl(regionId, dsoId),
		}, function(err, data, xhr) {
			if (scheduleKey === yasnoOutageManager.lastScheduleKey) {
				if (err) {
					logger.log('yasno.fetchAllCalendars.err', err, xhr && xhr.status)
				} else {
					var schedule = Yasno.parsePlannedOutages(data, yasnoOutageManager.group)
					if (!schedule) {
						logger.log('yasno: group not found in schedule', yasnoOutageManager.group)
					}
					yasnoOutageManager.lastSchedule = schedule
					if (schedule) {
						yasnoOutageManager.notifyDayKindChanges(schedule.dayKinds)
					}
				}
				setCalendarData(outageCalendarId, {
					"items": createEvents(yasnoOutageManager.lastSchedule),
				})
			}
			yasnoOutageManager.asyncRequestsDone += 1
		})
	}
}
