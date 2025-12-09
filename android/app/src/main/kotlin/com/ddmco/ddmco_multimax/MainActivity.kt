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

    // Netum C750 / Generic Scan Service Constants
    private val NETUM_INTENT_ACTION = "com.android.server.scannerservice.broadcast"
    private val NETUM_DATA_KEY = "scannerdata"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                private var receiver: BroadcastReceiver? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    receiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            val action = intent?.action
                            // Log incoming action for debugging
                            Log.d("ScanCheck", "Received Intent Action: $action")

                            var scanData: String? = null

                            // Handle Zebra
                            if (action == ZEBRA_INTENT_ACTION) {
                                scanData = intent.getStringExtra(ZEBRA_DATA_KEY)
                            }
                            // Handle Netum / Generic
                            else if (action == NETUM_INTENT_ACTION) {
                                scanData = intent.getStringExtra(NETUM_DATA_KEY)
                            }

                            if (!scanData.isNullOrEmpty()) {
                                val cleanData = scanData.trim() // Handle "Enter" key suffix
                                Log.d("ScanCheck", "Decoded Data: $cleanData")
                                events?.success(cleanData)
                            } else {
                                Log.d("ScanCheck", "Scan data was null or empty")
                            }
                        }
                    }

                    val filter = IntentFilter()
                    filter.addAction(ZEBRA_INTENT_ACTION)
                    filter.addAction(NETUM_INTENT_ACTION)
                    filter.addCategory(Intent.CATEGORY_DEFAULT)

                    // Critical for Android 13+ (API 33): Export the receiver to allow external apps to send to it
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
                    } else {
                        context.registerReceiver(receiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    if (receiver != null) {
                        context.unregisterReceiver(receiver)
                        receiver = null
                    }
                }
            }
        )

        createDataWedgeProfile()
    }

    private fun createDataWedgeProfile() {
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