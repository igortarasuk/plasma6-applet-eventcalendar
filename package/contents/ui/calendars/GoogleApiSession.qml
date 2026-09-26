import QtQuick 2.0

import "../lib/Requests.js" as Requests

QtObject {
	id: googleApiSession

	// Empty for the first account, "account2" for the second one.
	property string accountPrefix: ""
	function cfgKey(key) {
		return accountPrefix ? accountPrefix + key.charAt(0).toUpperCase() + key.slice(1) : key
	}
	function cfg(key) {
		return plasmoid.configuration[cfgKey(key)]
	}

	readonly property string accessToken: plasmoid.configuration[cfgKey("accessToken")] || ""
	property bool refreshInProgress: false
	property var refreshWaiters: []

	//--- Refresh Credentials
	function checkAccessToken(callback) {
		logger.debug('checkAccessToken')
		if (cfg("accessTokenExpiresAt") < Date.now() + 5000) {
			updateAccessToken(callback)
		} else {
			callback(null)
		}
	}

	function updateAccessToken(callback) {
		refreshWaiters.push(callback)
		if (refreshInProgress) return
		refreshInProgress = true
		function finishRefresh(err) {
			var waiters = refreshWaiters.slice(0)
			refreshWaiters = []
			refreshInProgress = false
			for (var i = 0; i < waiters.length; i++) waiters[i](err || null)
		}
		// logger.debug('accessTokenExpiresAt', cfg("accessTokenExpiresAt"))
		// logger.debug('                 now', Date.now())
		// logger.debug('refreshToken', cfg("refreshToken"))
		if (cfg("refreshToken")) {
			logger.debug('updateAccessToken')
			fetchNewAccessToken(function(err, data, xhr) {
				var tokenData = null
				if (!err) {
					try {
						tokenData = typeof data === 'string' ? JSON.parse(data) : data
					} catch (parseError) {
						err = "Invalid response while refreshing Google access token."
					}
				}
				if (err || (tokenData && tokenData.error)) {
					logger.log('Error when using refreshToken:', err, data)
					return finishRefresh(err || "Failed to refresh Google access token.")
				}
				if (!tokenData || !tokenData.access_token) {
					return finishRefresh("Missing access token in Google refresh response.")
				}
				logger.debug('onAccessToken', tokenData)

				googleApiSession.applyAccessToken(tokenData)

				finishRefresh(null)
			})
		} else {
			finishRefresh('No refresh token. Cannot update access token.')
		}
	}

	signal accessTokenError(string msg)
	signal newAccessToken()
	signal transactionError(string msg)

	onTransactionError: logger.log(msg)

	function applyAccessToken(data) {
		plasmoid.configuration[cfgKey("accessToken")] = data.access_token
		plasmoid.configuration[cfgKey("accessTokenType")] = data.token_type
		plasmoid.configuration[cfgKey("accessTokenExpiresAt")] = Date.now() + data.expires_in * 1000
		newAccessToken()
	}

	function fetchNewAccessToken(callback) {
		logger.debug('fetchNewAccessToken')
		var url = "https://oauth2.googleapis.com/token"
		Requests.post({
			url: url,
			data: {
				client_id: cfg("sessionClientId"),
				client_secret: cfg("sessionClientSecret"),
				refresh_token: cfg("refreshToken"),
				grant_type: 'refresh_token',
			},
		}, callback)
	}


	//---
	property int errorCount: 0
	function getErrorTimeout(n) {
		// Exponential Backoff
		// 43200 seconds is 12 hours, which is a reasonable polling limit when the API is down.
		// After 6 errors, we wait an entire minute.
		// After 11 errors, we wait an entire hour.
		// After 15 errors, we will have waited 9 hours.
		// 16 errors and above uses the upper limit of 12 hour intervals.
		return 1000 * Math.min(43200, Math.pow(2, n))
	}
	// https://stackoverflow.com/questions/28507619/how-to-create-delay-function-in-qml
	function delay(delayTime, callback) {
		var timer = Qt.createQmlObject("import QtQuick 2.0; Timer {}", googleApiSession)
		timer.interval = delayTime
		timer.repeat = false
		timer.triggered.connect(callback)
		timer.triggered.connect(function release(){
			timer.triggered.disconnect(callback)
			timer.triggered.disconnect(release)
			timer.destroy()
		})
		timer.start()
	}
	function waitForErrorTimeout(callback) {
		errorCount += 1
		var timeout = getErrorTimeout(errorCount)
		delay(timeout, function(){
			callback()
		})
	}
}
