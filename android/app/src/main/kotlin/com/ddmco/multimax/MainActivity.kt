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
    private val NETUM_INTENT_ACTION = "com.android.server.scannerservice.broadcast"
    private val NETUM_DATA_KEY = "scannerdata"

    private var eventSink: EventChannel.EventSink? = null

    // 1. Define Receiver as a class property so it persists
    private val scanReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action
            // Debug Log: If this prints, the Intent connection is working!
            Log.d("ScanCheck", "Broadcast Received. Action: $action")

            var scanData: String? = null

            if (action == ZEBRA_INTENT_ACTION) {
                scanData = intent.getStringExtra(ZEBRA_DATA_KEY)
                Log.d("ScanCheck", "Source: Zebra | Data: $scanData")
            } else if (action == NETUM_INTENT_ACTION) {
                scanData = intent.getStringExtra(NETUM_DATA_KEY)
                Log.d("ScanCheck", "Source: Netum | Data: $scanData")
            }

            if (!scanData.isNullOrEmpty()) {
                val cleanData = scanData.trim()
                Log.d("ScanCheck", "Sending to Flutter: $cleanData")
                eventSink?.success(cleanData)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d("ScanCheck", "Flutter EventChannel Listener Connected")
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 2. Register Receiver Immediately (Robustness)
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
            Log.d("ScanCheck", "Native Receiver Registered in onCreate")
        } catch (e: Exception) {
            Log.e("ScanCheck", "Error registering receiver: ${e.message}")
        }

        // 3. Configure DataWedge
        configureDataWedge()
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(scanReceiver)
        } catch (e: Exception) {
            // Receiver might not have been registered
        }
    }

    private fun configureDataWedge() {
        // --- Step 1: Create Profile & Associate App ---
        val profileConfig = Bundle()
        profileConfig.putString("PROFILE_NAME", ZEBRA_PROFILE_NAME)
        profileConfig.putString("PROFILE_ENABLED", "true")
        profileConfig.putString("CONFIG_MODE", "CREATE_IF_NOT_EXIST")

        val appConfig = Bundle()
        appConfig.putString("PACKAGE_NAME", packageName)
        appConfig.putStringArray("ACTIVITY_LIST", arrayOf("*"))
        profileConfig.putParcelableArray("APP_LIST", arrayOf(appConfig))

        sendDataWedgeIntent("com.symbol.datawedge.api.SET_CONFIG", profileConfig)

        // --- Step 2: Configure Barcode Input (Enable QR/EAN) ---
        val barcodeConfig = Bundle()
        barcodeConfig.putString("PLUGIN_NAME", "BARCODE")
        barcodeConfig.putString("RESET_CONFIG", "true")

        val barcodeProps = Bundle()
        barcodeProps.putString("scanner_selection", "auto")
        barcodeProps.putString("decoder_ean13", "true")
        barcodeProps.putString("decoder_ean8", "true")
        barcodeProps.putString("decoder_qrcode", "true")

        barcodeConfig.putBundle("PARAM_LIST", barcodeProps)

        val barcodeProfile = Bundle()
        barcodeProfile.putString("PROFILE_NAME", ZEBRA_PROFILE_NAME)
        barcodeProfile.putString("PROFILE_ENABLED", "true")
        barcodeProfile.putString("CONFIG_MODE", "UPDATE")
        barcodeProfile.putBundle("PLUGIN_CONFIG", barcodeConfig)

        sendDataWedgeIntent("com.symbol.datawedge.api.SET_CONFIG", barcodeProfile)

        // --- Step 3: DISABLE Keystroke Output (Crucial Fix) ---
        // This stops the scanner from typing into text fields, ensuring only Intent output works
        val keystrokeConfig = Bundle()
        keystrokeConfig.putString("PLUGIN_NAME", "KEYSTROKE")
        keystrokeConfig.putString("RESET_CONFIG", "true")

        val keystrokeProps = Bundle()
        keystrokeProps.putString("keystroke_output_enabled", "false") // <--- DISABLE HERE

        keystrokeConfig.putBundle("PARAM_LIST", keystrokeProps)

        val keystrokeProfile = Bundle()
        keystrokeProfile.putString("PROFILE_NAME", ZEBRA_PROFILE_NAME)
        keystrokeProfile.putString("PROFILE_ENABLED", "true")
        keystrokeProfile.putString("CONFIG_MODE", "UPDATE")
        keystrokeProfile.putBundle("PLUGIN_CONFIG", keystrokeConfig)

        sendDataWedgeIntent("com.symbol.datawedge.api.SET_CONFIG", keystrokeProfile)

        // --- Step 4: ENABLE Intent Output ---
        val intentConfig = Bundle()
        intentConfig.putString("PLUGIN_NAME", "INTENT")
        intentConfig.putString("RESET_CONFIG", "true")

        val intentProps = Bundle()
        intentProps.putString("intent_output_enabled", "true")
        intentProps.putString("intent_action", ZEBRA_INTENT_ACTION)
        intentProps.putString("intent_delivery", "2") // 2 = Broadcast

        intentConfig.putBundle("PARAM_LIST", intentProps)

        val intentProfile = Bundle()
        intentProfile.putString("PROFILE_NAME", ZEBRA_PROFILE_NAME)
        intentProfile.putString("PROFILE_ENABLED", "true")
        intentProfile.putString("CONFIG_MODE", "UPDATE")
        intentProfile.putBundle("PLUGIN_CONFIG", intentConfig)

        sendDataWedgeIntent("com.symbol.datawedge.api.SET_CONFIG", intentProfile)

        Log.d("ScanCheck", "DataWedge Configuration Intents Sent")
    }

    private fun sendDataWedgeIntent(action: String, extra: Bundle) {
        val i = Intent()
        i.action = action
        i.putExtra(action.substringAfterLast("."), extra)
        sendBroadcast(i)
    }
}