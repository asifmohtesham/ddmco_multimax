package com.ddmco.multimax

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val EVENT_CHANNEL = "com.ddmco.multimax/scan"

    // Zebra DataWedge Constants
    private val ZEBRA_PROFILE_NAME = "MultimaxProfile"
    private val ZEBRA_INTENT_ACTION = "com.ddmco.multimax.SCAN"
    private val ZEBRA_DATA_KEY = "com.symbol.datawedge.data_string"

    // Netum C750 / Netum Scan Service Constants
    // Documentation refers to this as the default broadcast for Netum Android integration
    private val NETUM_INTENT_ACTION = "com.android.server.scannerservice.broadcast"
    private val NETUM_DATA_KEY = "scannerdata"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Initialize EventChannel for scanning events
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var receiver: BroadcastReceiver? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            val action = intent?.action
                            var scanData: String? = null

                            // Handle Zebra Scan
                            if (action == ZEBRA_INTENT_ACTION) {
                                scanData = intent.getStringExtra(ZEBRA_DATA_KEY)
                            }
                            // Handle Netum Scan
                            else if (action == NETUM_INTENT_ACTION) {
                                scanData = intent.getStringExtra(NETUM_DATA_KEY)
                            }

                            if (!scanData.isNullOrEmpty()) {
                                // Send to Flutter
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

        // 2. Configure DataWedge Profile (Zebra specific)
        createDataWedgeProfile()
    }

    private fun createDataWedgeProfile() {
        // Main Bundle to Create/Config Profile
        val profileConfig = Bundle()
        profileConfig.putString("PROFILE_NAME", ZEBRA_PROFILE_NAME)
        profileConfig.putString("PROFILE_ENABLED", "true")
        profileConfig.putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST")

        // APP_LIST: Associate this profile with our App Package
        val appConfig = Bundle()
        appConfig.putString("PACKAGE_NAME", packageName)
        appConfig.putStringArray("ACTIVITY_LIST", arrayOf("*"))
        profileConfig.putParcelableArray("APP_LIST", arrayOf(appConfig))

        // PLUGIN_CONFIG: Configure Barcode Input
        val barcodeConfig = Bundle()
        barcodeConfig.putString("PLUGIN_NAME", "BARCODE")
        barcodeConfig.putString("RESET_CONFIG", "true")

        val barcodeProps = Bundle()
        barcodeProps.putString("scanner_selection", "auto")
        barcodeProps.putString("decoder_ean13", "true")
        barcodeProps.putString("decoder_ean8", "true")
        // Enable QR Code for {ean-batch_no} pattern support
        barcodeProps.putString("decoder_qrcode", "true")

        // Enabling NG SimulScan properties (if supported by device hardware)
        // This improves capture for complex forms/multi-barcode scenarios
        barcodeProps.putString("scanning_mode", "1") // 1 = Single, 2 = UDI, 3 = MultiBarcode

        barcodeConfig.putBundle("PARAM_LIST", barcodeProps)
        profileConfig.putBundle("PLUGIN_CONFIG", barcodeConfig)

        // Send Intent to set APP_LIST and BARCODE plugin
        val setConfigIntent = Intent()
        setConfigIntent.action = "com.symbol.datawedge.api.ACTION"
        setConfigIntent.putExtra("com.symbol.datawedge.api.SET_CONFIG", profileConfig)
        sendBroadcast(setConfigIntent)

        // PLUGIN_CONFIG: Configure Intent Output
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
        intentProps.putString("intent_delivery", "2") // 2 = Broadcast

        intentPluginConfig.putBundle("PARAM_LIST", intentProps)
        intentConfig.putBundle("PLUGIN_CONFIG", intentPluginConfig)

        // Send Intent to set INTENT plugin
        val setIntentConfig = Intent()
        setIntentConfig.action = "com.symbol.datawedge.api.ACTION"
        setIntentConfig.putExtra("com.symbol.datawedge.api.SET_CONFIG", intentConfig)
        sendBroadcast(setIntentConfig)
    }
}