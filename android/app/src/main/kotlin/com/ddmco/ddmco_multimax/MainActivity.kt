package com.ddmco.multimax // Updated Package Name

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    // Channel name must match lib/data/services/data_wedge_service.dart
    private val EVENT_CHANNEL = "com.ddmco.multimax/scan"

    // Zebra DataWedge Constants
    private val ZEBRA_PROFILE_NAME = "MultimaxProfile"
    private val ZEBRA_INTENT_ACTION = "com.ddmco.multimax.SCAN"
    private val ZEBRA_DATA_KEY = "com.symbol.datawedge.data_string"

    // Netum C750 / Netum Scan Service Constants
    private val NETUM_INTENT_ACTION = "com.android.server.scannerservice.broadcast"
    private val NETUM_DATA_KEY = "scannerdata"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Initialize EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var receiver: BroadcastReceiver? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            val action = intent?.action
                            var scanData: String? = null

                            // Handle Zebra
                            if (action == ZEBRA_INTENT_ACTION) {
                                scanData = intent.getStringExtra(ZEBRA_DATA_KEY)
                            }
                            // Handle Netum
                            else if (action == NETUM_INTENT_ACTION) {
                                scanData = intent.getStringExtra(NETUM_DATA_KEY)
                            }

                            if (!scanData.isNullOrEmpty()) {
                                events?.success(scanData)
                            }
                        }
                    }

                    val filter = IntentFilter()
                    filter.addAction(ZEBRA_INTENT_ACTION)
                    filter.addAction(NETUM_INTENT_ACTION)
                    filter.addCategory(Intent.CATEGORY_DEFAULT)
                    context.registerReceiver(receiver, filter)
                }

                override fun onCancel(arguments: Any?) {
                    if (receiver != null) {
                        context.unregisterReceiver(receiver)
                        receiver = null
                    }
                }
            }
        )

        // 2. Configure Zebra DataWedge Profile
        createDataWedgeProfile()
    }

    private fun createDataWedgeProfile() {
        val profileConfig = Bundle()
        profileConfig.putString("PROFILE_NAME", ZEBRA_PROFILE_NAME)
        profileConfig.putString("PROFILE_ENABLED", "true")
        profileConfig.putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST")

        // APP_LIST: Associate profile with the app package
        val appConfig = Bundle()
        appConfig.putString("PACKAGE_NAME", packageName) // dynamically uses com.ddmco.multimax
        appConfig.putStringArray("ACTIVITY_LIST", arrayOf("*"))
        profileConfig.putParcelableArray("APP_LIST", arrayOf(appConfig))

        // PLUGIN_CONFIG: Barcode Input
        val barcodeConfig = Bundle()
        barcodeConfig.putString("PLUGIN_NAME", "BARCODE")
        barcodeConfig.putString("RESET_CONFIG", "true")

        val barcodeProps = Bundle()
        barcodeProps.putString("scanner_selection", "auto")
        barcodeProps.putString("decoder_ean13", "true")
        barcodeProps.putString("decoder_ean8", "true")
        barcodeProps.putString("decoder_qrcode", "true") // QR Support
        barcodeProps.putString("scanning_mode", "1")

        barcodeConfig.putBundle("PARAM_LIST", barcodeProps)
        profileConfig.putBundle("PLUGIN_CONFIG", barcodeConfig)

        val setConfigIntent = Intent()
        setConfigIntent.action = "com.symbol.datawedge.api.ACTION"
        setConfigIntent.putExtra("com.symbol.datawedge.api.SET_CONFIG", profileConfig)
        sendBroadcast(setConfigIntent)

        // PLUGIN_CONFIG: Intent Output
        val intentConfig = Bundle()
        intentConfig.putString("PROFILE_NAME", ZEBRA_PROFILE_NAME)
        intentConfig.putString("PROFILE_ENABLED", "true")
        intentConfig.putString("CONFIG_MODE", "UPDATE")

        val intentPluginConfig = Bundle()
        intentPluginConfig.putString("PLUGIN_NAME", "INTENT")
        intentPluginConfig.putString("RESET_CONFIG", "true")

        val intentProps = Bundle()
        intentProps.putString("intent_output_enabled", "true")
        intentProps.putString("intent_action", ZEBRA_INTENT_ACTION)
        intentProps.putString("intent_delivery", "2") // Broadcast

        intentPluginConfig.putBundle("PARAM_LIST", intentProps)
        intentConfig.putBundle("PLUGIN_CONFIG", intentPluginConfig)

        val setIntentConfig = Intent()
        setIntentConfig.action = "com.symbol.datawedge.api.ACTION"
        setIntentConfig.putExtra("com.symbol.datawedge.api.SET_CONFIG", intentConfig)
        sendBroadcast(setIntentConfig)
    }
}