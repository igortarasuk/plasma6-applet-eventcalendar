.pragma library

// Air raid alerts from https://siren.pp.ua, a public mirror of the
// ukrainealarm.com API. No API key required.

var baseUrl = 'https://siren.pp.ua/api/v3'

// https://siren.pp.ua/api/v3/regions (regionType == "State")
var regionList = [
	{ value: '31', text: 'м. Київ' },
	{ value: '14', text: 'Київська область' },
	{ value: '4', text: 'Вінницька область' },
	{ value: '8', text: 'Волинська область' },
	{ value: '9', text: 'Дніпропетровська область' },
	{ value: '28', text: 'Донецька область' },
	{ value: '10', text: 'Житомирська область' },
	{ value: '11', text: 'Закарпатська область' },
	{ value: '12', text: 'Запорізька область' },
	{ value: '564', text: 'м. Запоріжжя та Запорізька територіальна громада' },
	{ value: '13', text: 'Івано-Франківська область' },
	{ value: '15', text: 'Кіровоградська область' },
	{ value: '16', text: 'Луганська область' },
	{ value: '27', text: 'Львівська область' },
	{ value: '17', text: 'Миколаївська область' },
	{ value: '18', text: 'Одеська область' },
	{ value: '19', text: 'Полтавська область' },
	{ value: '5', text: 'Рівненська область' },
	{ value: '20', text: 'Сумська область' },
	{ value: '21', text: 'Тернопільська область' },
	{ value: '22', text: 'Харківська область' },
	{ value: '1293', text: 'м. Харків та Харківська територіальна громада' },
	{ value: '23', text: 'Херсонська область' },
	{ value: '3', text: 'Хмельницька область' },
	{ value: '24', text: 'Черкаська область' },
	{ value: '26', text: 'Чернівецька область' },
	{ value: '25', text: 'Чернігівська область' },
	{ value: '9999', text: 'Автономна Республіка Крим' },
]

function getRegionName(regionId) {
	for (var i = 0; i < regionList.length; i++) {
		if (regionList[i].value == regionId) {
			return regionList[i].text
		}
	}
	return ''
}

function alertsUrl(regionId) {
	return baseUrl + '/alerts/' + encodeURIComponent(regionId)
}

var levelSeverity = {
	'none': 0,
	'yellow': 1,
	'red': 2,
}

/* Reduce the active alerts of a region to its most severe level.
** data = [
** 	{
** 		regionId: "31",
** 		regionName: "м. Київ",
** 		activeAlerts: [
** 			{
** 				type: "AIR",
** 				lastUpdate: "2026-10-09T06:01:42.728205Z",
** 				activeAlertLevels: [
** 					{ alertLevel: "Yellow", reason: "Дронова загроза (жовтий рівень)", createdAt: "2026-10-09T06:01:42.782602Z" },
** 				],
** 			},
** 		],
** 	},
** ]
** @returns: null if the region isn't in the response, otherwise {
** 	level: 'none', // or 'yellow', 'red'
** 	reason: 'Дронова загроза (жовтий рівень)', // Can be empty
** 	since: '2026-10-09T06:01:42.782602Z', // Can be empty
** }
*/
function parseAlerts(data, regionId) {
	var region = null
	for (var i = 0; data && i < data.length; i++) {
		if (data[i] && data[i].regionId == regionId) {
			region = data[i]
			break
		}
	}
	if (!region) {
		return null
	}

	var result = { level: 'none', reason: '', since: '' }
	function consider(level, reason, since) {
		if (levelSeverity[level] > levelSeverity[result.level]) {
			result.level = level
			result.reason = reason || ''
			result.since = since || ''
		}
	}

	var activeAlerts = region.activeAlerts || []
	for (var i = 0; i < activeAlerts.length; i++) {
		var alert = activeAlerts[i]
		var levels = alert.activeAlertLevels || []
		if (levels.length === 0) {
			// An alert without a level is a regular (full) alert.
			consider('red', '', alert.lastUpdate)
		}
		for (var j = 0; j < levels.length; j++) {
			var alertLevel = ('' + levels[j].alertLevel).toLowerCase()
			// Treat levels we don't know about as the most severe one.
			var level = alertLevel === 'yellow' ? 'yellow' : 'red'
			consider(level, levels[j].reason, levels[j].createdAt || alert.lastUpdate)
		}
	}
	return result
}
