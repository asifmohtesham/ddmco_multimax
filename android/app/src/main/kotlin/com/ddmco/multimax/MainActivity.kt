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
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val EVENT_CHANNEL = "com.ddmco.multimax/scan"
    private val COMMAND_CHANNEL = "com.ddmco.multimax/command" // New Channel

    // Zebra DataWedge Constants
    private val ZEBRA_PROFILE_NAME = "MultimaxProfile"
    private val ZEBRA_INTENT_ACTION = "com.ddmco.multimax.SCAN"
    private val ZEBRA_DATA_KEY = "com.symbol.datawedge.data_string"
    // New Key for MultiBarcode/SimulScan Output
    private val ZEBRA_DATA_KEY_LIST = "com.symbol.datawedge.data_string_list"

    // DataWedge API Constants (New)
    private val DW_API_ACTION = "com.symbol.datawedge.api.ACTION"
    private val DW_RESULT_ACTION = "com.symbol.datawedge.api.RESULT_ACTION"
    private val DW_GET_VERSION = "com.symbol.datawedge.api.GET_VERSION_INFO"
    private val DW_RESULT_VERSION_KEY = "com.symbol.datawedge.api.RESULT_GET_VERSION_INFO"

    // Netum / Generic Scanner Constants
    private val NETUM_INTENT_ACTION = "com.android.server.scannerservice.broadcast"
    private val NETUM_DATA_KEY = "scannerdata"

    private var eventSink: EventChannel.EventSink? = null
    private var versionResult: MethodChannel.Result? = null // To hold the pending result

    // 1. Define Receiver as a class property so it persists
    private val scanReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action
            Log.d("ScanCheck", "Broadcast Received. Action: $action")

            if (action == ZEBRA_INTENT_ACTION) {
                // Check for MultiBarcode List first
                if (intent.hasExtra(ZEBRA_DATA_KEY_LIST)) {
                    val scanList = intent.getStringArrayListExtra(ZEBRA_DATA_KEY_LIST)
                    if (!scanList.isNullOrEmpty()) {
                        Log.d("ScanCheck", "Source: Zebra Multi | Data: $scanList")
                        // Send the entire list to Flutter
                        eventSink?.success(scanList)
                        return
                    }
                }

                // Fallback to Single Barcode
                val scanData = intent.getStringExtra(ZEBRA_DATA_KEY)
                Log.d("ScanCheck", "Source: Zebra Single | Data: $scanData")
                if (!scanData.isNullOrEmpty()) {
                    eventSink?.success(scanData.trim())
                }

            } else if (action == NETUM_INTENT_ACTION) {
                val scanData = intent.getStringExtra(NETUM_DATA_KEY)
                Log.d("ScanCheck", "Source: Netum | Data: $scanData")
                if (!scanData.isNullOrEmpty()) {
                    eventSink?.success(scanData.trim())
                }
            } else if (action == DW_RESULT_ACTION) {
                // --- Handle DataWedge Version Result ---
                if (intent.hasExtra(DW_RESULT_VERSION_KEY)) {
                    val bundle = intent.getBundleExtra(DW_RESULT_VERSION_KEY)
                    val dwVersion = bundle?.getString("DATAWEDGE")

                    if (versionResult != null) {
                        if (dwVersion != null) {
                            versionResult?.success(dwVersion)
                        } else {
                            versionResult?.error("UNAVAILABLE", "Version not found", null)
                        }
                        versionResult = null // Clear callback
                    }
                }
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

        // New MethodChannel for Commands
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMMAND_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getDWVersion") {
                versionResult = result // Save result to answer later in Receiver

                // Send API Intent
                val i = Intent()
                i.action = DW_API_ACTION
                i.putExtra(DW_GET_VERSION, "") // Value is empty string per API specs
                sendBroadcast(i)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 2. Register Receiver Immediately (Robustness)
        val filter = IntentFilter()
        filter.addAction(ZEBRA_INTENT_ACTION)
        filter.addAction(NETUM_INTENT_ACTION)
        filter.addAction(DW_RESULT_ACTION) // Register API Result Action
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

        // --- Step 2: Configure Barcode Input (Enable QR/EAN + MultiBarcode) ---
        val barcodeConfig = Bundle()
        barcodeConfig.putString("PLUGIN_NAME", "BARCODE")
        barcodeConfig.putString("RESET_CONFIG", "true")

        val barcodeProps = Bundle()
        barcodeProps.putString("scanner_selection", "auto")
        barcodeProps.putString("decoder_ean13", "true")
        barcodeProps.putString("decoder_ean8", "true")
        barcodeProps.putString("decoder_qrcode", "true")

        // --- NEXTGEN SIMULSCAN / MULTIBARCODE CONFIGURATION ---
        // scanning_mode: 1=Single, 3=MultiBarcode (NextGen)
        barcodeProps.putString("scanning_mode", "3")
        // multi_barcode_count: Number of barcodes to capture (Set to 5 to be safe)
        barcodeProps.putString("multi_barcode_count", "5")
        // Optional: Instant reporting allows data to come in as decoded (improves speed)
        barcodeProps.putString("instant_reporting_enable", "true")

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