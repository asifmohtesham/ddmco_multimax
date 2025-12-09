package com.ddmco.multimax

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val EVENT_CHANNEL = "com.ddmco.multimax/scan"

    // Zebra DataWedge Constants
    private val ZEBRA_PROFILE_NAME = "MultimaxProfile"
    private val ZEBRA_INTENT_ACTION = "com.ddmco.multimax.SCAN"
    private val ZEBRA_DATA_KEY = "com.symbol.datawedge.data_string"

    // Netum / Generic Scanner Constants
    // Note: Confirm this action in your Netum Scanner's specific settings/manual
    private val NETUM_INTENT_ACTION = "com.android.server.scannerservice.broadcast"
    private val NETUM_DATA_KEY = "scannerdata"

    // Hold the event sink to send data to Flutter whenever we get it
    private var eventSink: EventChannel.EventSink? = null

    // Define the receiver as a property of the class
    private val scanReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action
            // 1. Log that we actually received SOMETHING
            Log.d("ScanCheck", "Native BroadcastReceiver onReceive. Action: $action")

            var scanData: String? = null

            // 2. Extract Data based on Source
            if (action == ZEBRA_INTENT_ACTION) {
                scanData = intent.getStringExtra(ZEBRA_DATA_KEY)
                Log.d("ScanCheck", "Source: Zebra. Data: $scanData")
            }
            else if (action == NETUM_INTENT_ACTION) {
                scanData = intent.getStringExtra(NETUM_DATA_KEY)
                Log.d("ScanCheck", "Source: Netum. Data: $scanData")
            }
            // Fallback: Dump all extras to Logcat if scanData is null (helps debug unknown keys)
            else {
                val bundle = intent?.extras
                if (bundle != null) {
                    for (key in bundle.keySet()) {
                        Log.d("ScanCheck", "Extra Key: $key, Value: ${bundle.get(key)}")
                    }
                }
            }

            // 3. Send to Flutter
            if (!scanData.isNullOrEmpty()) {
                val cleanData = scanData.trim()
                Log.d("ScanCheck", "Sending to Flutter: $cleanData")
                eventSink?.success(cleanData)
            } else {
                Log.w("ScanCheck", "Received Intent but data was empty or key mismatch.")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup the EventChannel to just capture the sink
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d("ScanCheck", "Flutter EventChannel connected")
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    Log.d("ScanCheck", "Flutter EventChannel disconnected")
                    eventSink = null
                }
            }
        )

        // Create the profile for Zebra devices
        createDataWedgeProfile()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Register the receiver immediately when the app starts
        val filter = IntentFilter()
        filter.addAction(ZEBRA_INTENT_ACTION)
        filter.addAction(NETUM_INTENT_ACTION)
        filter.addCategory(Intent.CATEGORY_DEFAULT)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(scanReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(scanReceiver, filter)
            }
            Log.d("ScanCheck", "BroadcastReceiver Registered Successfully in onCreate")
        } catch (e: Exception) {
            Log.e("ScanCheck", "Failed to register receiver: ${e.message}")
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(scanReceiver)
            Log.d("ScanCheck", "BroadcastReceiver Unregistered")
        } catch (e: Exception) {
            // Receiver might not have been registered
        }
        super.onDestroy()
    }

    private fun createDataWedgeProfile() {
        // ... (Keep existing DataWedge profile creation logic) ...
        val profileConfig = Bundle()
        profileConfig.putString("PROFILE_NAME", ZEBRA_PROFILE_NAME)
        profileConfig.putString("PROFILE_ENABLED", "true")
        profileConfig.putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST")

        val appConfig = Bundle()
        appConfig.putString("PACKAGE_NAME", packageName)
        appConfig.putStringArray("ACTIVITY_LIST", arrayOf("*"))
        profileConfig.putParcelableArray("APP_LIST", arrayOf(appConfig))

        val barcodeConfig = Bundle()
        barcodeConfig.putString("PLUGIN_NAME", "BARCODE")
        barcodeConfig.putString("RESET_CONFIG", "true")

        val barcodeProps = Bundle()
        barcodeProps.putString("scanner_selection", "auto")
        barcodeProps.putString("decoder_ean13", "true")
        barcodeProps.putString("decoder_ean8", "true")
        barcodeProps.putString("decoder_qrcode", "true")
        barcodeProps.putString("scanning_mode", "1")

        barcodeConfig.putBundle("PARAM_LIST", barcodeProps)
        profileConfig.putBundle("PLUGIN_CONFIG", barcodeConfig)

        val setConfigIntent = Intent()
        setConfigIntent.action = "com.symbol.datawedge.api.ACTION"
        setConfigIntent.putExtra("com.symbol.datawedge.api.SET_CONFIG", profileConfig)
        sendBroadcast(setConfigIntent)

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