import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications presents foreground notifications through
    // the notification-centre delegate. Without this, a digest reminder that
    // fires while the app is open is silently dropped.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Drops, stranded shares and Mac detection (channel com.ddmco.multimax/intake).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IntakeBridge") {
      IntakeBridge.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppUpdateReceipt") {
      let channel = FlutterMethodChannel(
        name: "com.ddmco.multimax/app_update", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "hasAppStoreReceipt" else {
          result(FlutterMethodNotImplemented)
          return
        }
        // package_info_plus also reports com.apple when the receipt is missing.
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
          result(false)
        #else
          guard !ProcessInfo.processInfo.isiOSAppOnMac,
            let receipt = Bundle.main.appStoreReceiptURL,
            receipt.lastPathComponent == "receipt"
          else {
            result(false)
            return
          }
          result(FileManager.default.fileExists(atPath: receipt.path))
        #endif
      }
    }
  }
}
