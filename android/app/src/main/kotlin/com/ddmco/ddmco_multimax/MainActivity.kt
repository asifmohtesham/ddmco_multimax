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
    private val PROFILE_NAME = "MultimaxProfile"
    private val SCAN_INTENT_ACTION = "com.ddmco.multimax.SCAN"

    // DataWedge Extras
    private val DATAWEDGE_INTENT_KEY_SOURCE = "com.symbol.datawedge.source"
    private val DATAWEDGE_INTENT_KEY_LABEL_TYPE = "com.symbol.datawedge.label_type"
    private val DATAWEDGE_INTENT_KEY_DATA = "com.symbol.datawedge.data_string"

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
                            if (action == SCAN_INTENT_ACTION) {
                                // Extract the string data from the intent
                                val scanData = intent.getStringExtra(DATAWEDGE_INTENT_KEY_DATA)
                                if (scanData != null) {
                                    // Send to Flutter
                                    events?.success(scanData)
                                }
                            }
                        }
                    }
                    val filter = IntentFilter()
                    filter.addAction(SCAN_INTENT_ACTION)
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

        // 2. Configure DataWedge Profile
        createDataWedgeProfile()
    }

    private fun createDataWedgeProfile() {
        // Main Bundle to Create/Config Profile
        val profileConfig = Bundle()
        profileConfig.putString("PROFILE_NAME", PROFILE_NAME)
        profileConfig.putString("PROFILE_ENABLED", "true")
        profileConfig.putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST") // Create if doesn't exist

        // APP_LIST: Associate this profile with our App Package
        val appConfig = Bundle()
        appConfig.putString("PACKAGE_NAME", packageName)
        appConfig.putStringArray("ACTIVITY_LIST", arrayOf("*"))
        profileConfig.putParcelableArray("APP_LIST", arrayOf(appConfig))

        // PLUGIN_CONFIG: Configure Barcode Input (NG SimulScan/Standard Engine)
        val barcodeConfig = Bundle()
        barcodeConfig.putString("PLUGIN_NAME", "BARCODE")
        barcodeConfig.putString("RESET_CONFIG", "true")

        val barcodeProps = Bundle()
        barcodeProps.putString("scanner_selection", "auto")
        barcodeProps.putString("decoder_ean13", "true") // EAN Support
        barcodeProps.putString("decoder_ean8", "true")  // EAN Support
        barcodeProps.putString("decoder_qrcode", "true") // QR Support for {ean-batch} pattern

        // "NG SimulScan" usually refers to advanced document capture, but for
        // standard QR/EAN inputs, enabling these decoders allows the engine
        // to act as the input source effectively.
        barcodeProps.putString("decoder_code128", "true")
        barcodeProps.putString("decoder_code39", "true")

        barcodeConfig.putBundle("PARAM_LIST", barcodeProps)
        profileConfig.putBundle("PLUGIN_CONFIG", barcodeConfig)

        // Send Intent to set APP_LIST and BARCODE plugin
        val setConfigIntent = Intent()
        setConfigIntent.action = "com.symbol.datawedge.api.ACTION"
        setConfigIntent.putExtra("com.symbol.datawedge.api.SET_CONFIG", profileConfig)
        sendBroadcast(setConfigIntent)

        // PLUGIN_CONFIG: Configure Intent Output (Send data to our BroadcastReceiver)
        val intentConfig = Bundle()
        intentConfig.putString("PROFILE_NAME", PROFILE_NAME)
        intentConfig.putString("PROFILE_ENABLED", "true")
        intentConfig.putString("CONFIG_MODE", "UPDATE") // Update existing profile

        val intentPluginConfig = Bundle()
        intentPluginConfig.putString("PLUGIN_NAME", "INTENT")
        intentPluginConfig.putString("RESET_CONFIG", "true")

        val intentProps = Bundle()
        intentProps.putString("intent_output_enabled", "true")
        intentProps.putString("intent_action", SCAN_INTENT_ACTION)
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