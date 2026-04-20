package com.powerman.powerman

import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val lanChannelName = "powerman/lan"
	private var multicastLock: WifiManager.MulticastLock? = null

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, lanChannelName)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"acquireMulticastLock" -> {
						acquireMulticastLock()
						result.success(true)
					}

					"releaseMulticastLock" -> {
						releaseMulticastLock()
						result.success(true)
					}

					else -> result.notImplemented()
				}
			}
	}

	private fun acquireMulticastLock() {
		if (multicastLock?.isHeld == true) return
		val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
		multicastLock = wifiManager.createMulticastLock("powerman_lan_multicast_lock").apply {
			setReferenceCounted(true)
			acquire()
		}
	}

	private fun releaseMulticastLock() {
		multicastLock?.let {
			if (it.isHeld) it.release()
		}
		multicastLock = null
	}

	override fun onDestroy() {
		releaseMulticastLock()
		super.onDestroy()
	}
}
