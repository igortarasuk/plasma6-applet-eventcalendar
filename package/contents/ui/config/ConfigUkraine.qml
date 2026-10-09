import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import ".."
import "../lib"
import "../lib/Requests.js" as Requests
import "../ukraine/UkraineAlarm.js" as UkraineAlarm
import "../ukraine/Yasno.js" as Yasno

ConfigPage {
	id: page

	readonly property var outageProvider: Yasno.getProvider(page.cfg_outageRegionId, page.cfg_outageDsoId)
	readonly property bool canLookupAddress: !!outageProvider && !outageProvider.hasCities
	property string lookupMessage: ""

	function lookup(url, callback) {
		page.lookupMessage = i18n("Searching…")
		Requests.getJSON({ url: url }, function(err, data) {
			if (err || !data) {
				page.lookupMessage = i18n("Search failed: %1", "" + err)
				return
			}
			page.lookupMessage = ""
			callback(data)
		})
	}

	function searchStreets() {
		var query = streetField.text.trim()
		if (!query) return
		lookup(Yasno.streetsUrl(page.cfg_outageRegionId, page.cfg_outageDsoId, query), function(data) {
			streetCombo.model = data
			houseCombo.model = []
			if (data.length === 0) {
				page.lookupMessage = i18n("Street not found.")
			}
		})
	}

	function searchHouses() {
		var street = streetCombo.model[streetCombo.currentIndex]
		var query = houseField.text.trim()
		if (!street || !query) return
		lookup(Yasno.housesUrl(page.cfg_outageRegionId, page.cfg_outageDsoId, street.id, query), function(data) {
			houseCombo.model = data
			if (data.length === 0) {
				page.lookupMessage = i18n("House not found.")
			} else {
				page.selectHouse()
			}
		})
	}

	function selectHouse() {
		var street = streetCombo.model[streetCombo.currentIndex]
		var house = houseCombo.model[houseCombo.currentIndex]
		if (!street || !house) return
		lookup(Yasno.groupUrl(page.cfg_outageRegionId, page.cfg_outageDsoId, street.id, house.id), function(data) {
			var group = Yasno.formatGroup(data)
			if (group) {
				page.cfg_outageGroup = group
			} else {
				page.lookupMessage = i18n("Group not found.")
			}
		})
	}

	ColumnLayout {
		Layout.fillWidth: true
		spacing: Kirigami.Units.largeSpacing

		ConfigSection {
			title: i18n("Power outage schedule")

			Kirigami.FormLayout {
				Layout.fillWidth: true

				ConfigCheckBox {
					Kirigami.FormData.label: ""
					configKey: "outageEnabled"
					text: i18n("Show planned power outages as events (Yasno)")
				}

				QQC2.ComboBox {
					id: providerCombo
					Kirigami.FormData.label: i18n("Provider:")
					Layout.fillWidth: true
					textRole: "text"
					model: Yasno.providerList

					function syncFromCfg() {
						for (var i = 0; i < model.length; i++) {
							if (model[i].regionId == page.cfg_outageRegionId && model[i].dsoId == page.cfg_outageDsoId) {
								currentIndex = i
								return
							}
						}
					}

					Component.onCompleted: syncFromCfg()
					onActivated: {
						page.cfg_outageRegionId = model[currentIndex].regionId
						page.cfg_outageDsoId = model[currentIndex].dsoId
						streetCombo.model = []
						houseCombo.model = []
					}
				}

				ConfigString {
					Kirigami.FormData.label: i18n("Group:")
					configKey: "outageGroup"
					placeholderText: i18nc("power outage group example", "Eg: 1.1")
				}

				ConfigCheckBox {
					Kirigami.FormData.label: ""
					configKey: "outageNotify"
					text: i18n("Notify about emergency power outages")
				}

				Kirigami.Separator {
					Kirigami.FormData.isSection: true
					Kirigami.FormData.label: i18n("Find the group by address")
					visible: page.canLookupAddress
				}

				RowLayout {
					Kirigami.FormData.label: i18n("Street:")
					visible: page.canLookupAddress

					QQC2.TextField {
						id: streetField
						Layout.fillWidth: true
						onAccepted: page.searchStreets()
					}
					QQC2.Button {
						text: i18n("Search…")
						onClicked: page.searchStreets()
					}
				}

				QQC2.ComboBox {
					id: streetCombo
					Kirigami.FormData.label: ""
					Layout.fillWidth: true
					visible: page.canLookupAddress && count > 0
					textRole: "value"
					model: []
					onActivated: houseCombo.model = []
				}

				RowLayout {
					Kirigami.FormData.label: i18n("House:")
					visible: page.canLookupAddress && streetCombo.count > 0

					QQC2.TextField {
						id: houseField
						Layout.fillWidth: true
						onAccepted: page.searchHouses()
					}
					QQC2.Button {
						text: i18n("Search…")
						onClicked: page.searchHouses()
					}
				}

				QQC2.ComboBox {
					id: houseCombo
					Kirigami.FormData.label: ""
					Layout.fillWidth: true
					visible: page.canLookupAddress && count > 0
					textRole: "value"
					model: []
					onActivated: page.selectHouse()
				}

				QQC2.Label {
					Kirigami.FormData.label: ""
					visible: !!text
					text: page.lookupMessage
				}
			}
		}

		ConfigSection {
			title: i18n("Air raid alerts")

			Kirigami.FormLayout {
				Layout.fillWidth: true

				ConfigCheckBox {
					Kirigami.FormData.label: ""
					configKey: "alertEnabled"
					text: i18n("Show the alert level next to the clock")
				}

				ConfigComboBox {
					Kirigami.FormData.label: i18n("Region:")
					configKey: "alertRegionId"
					model: UkraineAlarm.regionList
				}

				ConfigSpinBox {
					Kirigami.FormData.label: i18n("Check every:")
					configKey: "alertPollInterval"
					minimumValue: 10
					maximumValue: 600
					suffix: i18nc("seconds", " s")
				}

				ConfigCheckBox {
					Kirigami.FormData.label: ""
					configKey: "alertNotify"
					text: i18n("Notify when the alert level changes")
				}
			}
		}
	}
}
