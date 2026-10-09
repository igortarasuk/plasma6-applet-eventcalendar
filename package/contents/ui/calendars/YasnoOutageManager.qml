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
	readonly property bool outagesEnabled: plasmoid.configuration.outageEnabled && Yasno.isGroupValid(group)

	// Keep showing the last known schedule when a refresh fails.
	property var lastSchedule: null
	property string lastScheduleKey: ""

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
		return items
	}

	onFetchAllCalendars: {
		if (!outagesEnabled) {
			return
		}
		var regionId = plasmoid.configuration.outageRegionId
		var dsoId = plasmoid.configuration.outageDsoId
		var scheduleKey = [regionId, dsoId, group].join('/')
		if (scheduleKey !== lastScheduleKey) {
			lastSchedule = null
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
				}
				setCalendarData(outageCalendarId, {
					"items": createEvents(yasnoOutageManager.lastSchedule),
				})
			}
			yasnoOutageManager.asyncRequestsDone += 1
		})
	}
}
