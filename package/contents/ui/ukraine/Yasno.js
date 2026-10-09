.pragma library

// Planned power outage schedules published by Yasno (https://yasno.ua).
// No API key required.

var baseUrl = 'https://app.yasno.ua/api/blackout-service/public/shutdowns'
var websiteUrl = 'https://static.yasno.ua/kyiv/outages'

// Distribution system operators covered by Yasno.
// The street/house lookup only works where a region isn't split into cities.
var providerList = [
	{ regionId: 25, dsoId: 902, text: 'Київ — ДТЕК Київські електромережі', hasCities: false },
	{ regionId: 3, dsoId: 301, text: 'Дніпро — ДнЕМ', hasCities: true },
	{ regionId: 3, dsoId: 303, text: 'Дніпро — ЦЕК', hasCities: true },
]

function getProvider(regionId, dsoId) {
	for (var i = 0; i < providerList.length; i++) {
		var provider = providerList[i]
		if (provider.regionId == regionId && provider.dsoId == dsoId) {
			return provider
		}
	}
	return null
}

function plannedOutagesUrl(regionId, dsoId) {
	return baseUrl + '/regions/' + encodeURIComponent(regionId) + '/dsos/' + encodeURIComponent(dsoId) + '/planned-outages'
}

function addressUrl(resource, params) {
	var query = []
	for (var key in params) {
		query.push(encodeURIComponent(key) + '=' + encodeURIComponent(params[key]))
	}
	return baseUrl + '/addresses/v2/' + resource + '?' + query.join('&')
}

function streetsUrl(regionId, dsoId, query) {
	return addressUrl('streets', { regionId: regionId, dsoId: dsoId, query: query })
}

function housesUrl(regionId, dsoId, streetId, query) {
	return addressUrl('houses', { regionId: regionId, dsoId: dsoId, streetId: streetId, query: query })
}

function groupUrl(regionId, dsoId, streetId, houseId) {
	return addressUrl('group', { regionId: regionId, dsoId: dsoId, streetId: streetId, houseId: houseId })
}

/* data = { group: 1, subgroup: 1 } */
function formatGroup(data) {
	if (!data || typeof data.group === 'undefined') {
		return ''
	}
	return data.group + '.' + data.subgroup
}

function isGroupValid(group) {
	return /^\d+\.\d+$/.test(('' + group).trim())
}

function nextDateString(dateString) {
	var parts = dateString.split('-')
	var d = new Date(Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]) + 1))
	return d.toISOString().substr(0, 10)
}

/* Parse the schedule of a single group.
** data = {
** 	"1.1": {
** 		today: {
** 			slots: [ { start: 0, end: 90, type: "Definite" }, { start: 90, end: 1440, type: "NotPlanned" } ], // minutes
** 			date: "2026-10-09T00:00:00+03:00",
** 			status: "ScheduleApplies",
** 		},
** 		tomorrow: { ... },
** 		updatedOn: "2026-10-09T08:12:15+00:00",
** 	},
** 	...
** }
** @returns: null if the group isn't in the schedule, otherwise {
** 	outages: [ { start: 1791500400000, end: 1791505800000, definite: true }, ... ], // milliseconds
** 	emergencyDays: [ { start: "2026-10-09", end: "2026-10-10" }, ... ],
** 	unknownDays: [ { start: "2026-10-09", end: "2026-10-10", status: "SomeNewStatus" }, ... ],
** 	dayKinds: { "2026-10-09": "schedule", "2026-10-10": "waiting" }, // or "emergency", "unknown"
** 	updatedOn: "2026-10-09T08:12:15+00:00",
** }
*/
function parsePlannedOutages(data, group) {
	var groupData = data ? data[('' + group).trim()] : null
	if (!groupData) {
		return null
	}

	var outages = []
	var emergencyDays = []
	var unknownDays = []
	var dayKinds = {}
	var days = [groupData.today, groupData.tomorrow]
	for (var i = 0; i < days.length; i++) {
		var day = days[i]
		if (!day || !day.date) {
			continue
		}
		var dateString = day.date.substr(0, 10)
		if (day.status === 'EmergencyShutdowns') {
			dayKinds[dateString] = 'emergency'
			emergencyDays.push({ start: dateString, end: nextDateString(dateString) })
			continue
		}
		if (day.status === 'WaitingForSchedule') {
			dayKinds[dateString] = 'waiting'
			continue
		}
		if (day.status !== 'ScheduleApplies') {
			// Don't silently show an empty day for a status we don't know about.
			dayKinds[dateString] = 'unknown'
			unknownDays.push({ start: dateString, end: nextDateString(dateString), status: '' + day.status })
			continue
		}
		dayKinds[dateString] = 'schedule'
		var dayStart = Date.parse(day.date)
		var slots = day.slots || []
		for (var j = 0; j < slots.length; j++) {
			var slot = slots[j]
			if (slot.type === 'NotPlanned' || !(slot.end > slot.start)) {
				continue
			}
			outages.push({
				start: dayStart + slot.start * 60000,
				end: dayStart + slot.end * 60000,
				definite: slot.type === 'Definite',
			})
		}
	}

	// An outage that runs past midnight is split across today and tomorrow.
	outages.sort(function(a, b) { return a.start - b.start })
	var merged = []
	for (var i = 0; i < outages.length; i++) {
		var outage = outages[i]
		var prev = merged[merged.length - 1]
		if (prev && prev.end === outage.start && prev.definite === outage.definite) {
			prev.end = outage.end
		} else {
			merged.push(outage)
		}
	}

	return {
		outages: merged,
		emergencyDays: emergencyDays,
		unknownDays: unknownDays,
		dayKinds: dayKinds,
		updatedOn: groupData.updatedOn || '',
	}
}
