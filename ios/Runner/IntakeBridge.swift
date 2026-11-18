import Flutter
import UIKit
import UniformTypeIdentifiers

/// The native end of the intake channel `com.ddmco.multimax/intake`
/// (Dart: `lib/app/data/services/native_intake.dart`).
///
/// - `isRunningOnMac` → `Bool`: whether this iPhone/iPad app runs on a Mac.
/// - `sharedFolders` → `[String]`: the App Group container and
///   `NSTemporaryDirectory()/dropped`, the only folders whose photo copies
///   the app may delete.
/// - `takeStrandedShare` → `[String]`: the paths of a share the extension
///   left in the App Group without opening the app, once per share id.
/// - `markShareHandled`: records the current share id as handled.
/// - native → Dart `dropped` with `[String]`: photos dropped onto the window,
///   copied into `NSTemporaryDirectory()/dropped`.
///
/// On registration it also deletes photo copies older than a day left in
/// those two folders (by a crash, or a share that was never opened).
final class IntakeBridge: NSObject, FlutterPlugin, UIDropInteractionDelegate {
  static let channelName = "com.ddmco.multimax/intake"

  /// The App Group used when Info.plist has no `AppGroupId`.
  private static let defaultGroupId = "group.com.ddmco.multimax"
  /// receive_sharing_intent 1.9.0: the shared media as JSON in the group defaults.
  private static let shareKey = "ShareKey"
  /// Written by our share extension beside `ShareKey`, one UUID per share.
  private static let shareIdKey = "MultimaxShareId"
  /// The last share id the app dealt with, in the app's own defaults.
  private static let handledShareIdKey = "MultimaxHandledShareId"
  private static let droppedFolderName = "dropped"
  private static let sweepAge: TimeInterval = 24 * 60 * 60
  private static let sweptExtensions: Set<String> = [
    "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "webp",
  ]

  private let channel: FlutterMethodChannel
  private let registrar: FlutterPluginRegistrar
  private var dropInteractionAttached = false
  private var attachObservers: [NSObjectProtocol] = []

  private init(channel: FlutterMethodChannel, registrar: FlutterPluginRegistrar) {
    self.channel = channel
    self.registrar = registrar
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName, binaryMessenger: registrar.messenger())
    let instance = IntakeBridge(channel: channel, registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
    instance.attachDropInteractionWhenReady()
    DispatchQueue.global(qos: .utility).async { sweepOldCopies() }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isRunningOnMac":
      result(ProcessInfo.processInfo.isiOSAppOnMac)
    case "sharedFolders":
      result(Self.sharedFolderURLs().map { $0.path })
    case "takeStrandedShare":
      result(Self.takeStrandedShare())
    case "markShareHandled":
      Self.markShareHandled()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Folders

  private static var groupId: String {
    (Bundle.main.object(forInfoDictionaryKey: "AppGroupId") as? String)
      .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } ?? defaultGroupId
  }

  private static var groupContainerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
  }

  /// `NSTemporaryDirectory()/dropped`, created if missing; `nil` if it cannot be.
  private static func droppedFolderURL() -> URL? {
    let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(droppedFolderName, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    } catch {
      return nil
    }
  }

  /// Exactly the two folders, never a parent: the Dart side deletes the photos
  /// it is given only when they lie within these.
  private static func sharedFolderURLs() -> [URL] {
    [groupContainerURL, droppedFolderURL()].compactMap { $0 }
  }

  // MARK: - Stranded shares

  private static var groupDefaults: UserDefaults? { UserDefaults(suiteName: groupId) }

  private static func takeStrandedShare() -> [String] {
    guard let defaults = groupDefaults,
      let shareId = defaults.string(forKey: shareIdKey),
      shareId != UserDefaults.standard.string(forKey: handledShareIdKey),
      let data = defaults.data(forKey: shareKey),
      let entries = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    else { return [] }
    UserDefaults.standard.set(shareId, forKey: handledShareIdKey)
    return entries.compactMap { $0["path"] as? String }.map(filePath(from:))
  }

  private static func markShareHandled() {
    guard let shareId = groupDefaults?.string(forKey: shareIdKey) else { return }
    UserDefaults.standard.set(shareId, forKey: handledShareIdKey)
  }

  /// The share stores a percent-decoded file URL string ("file:///…"), which
  /// may not parse as a URL (a space or '#' in the name), so the scheme is
  /// stripped as the plugin's own `getAbsolutePath` does. Anything else goes
  /// through `URL(string:)`, or is passed on as it is.
  private static func filePath(from raw: String) -> String {
    let scheme = "file://"
    if raw.hasPrefix(scheme) { return String(raw.dropFirst(scheme.count)) }
    if let url = URL(string: raw), url.isFileURL { return url.path }
    return raw
  }

  // MARK: - Sweep

  /// Deletes photo copies older than a day directly in the App Group root and
  /// in `dropped/`. It never recurses, so `Library/` and the group's
  /// preferences are left alone.
  private static func sweepOldCopies() {
    let keys: [URLResourceKey] = [
      .isRegularFileKey, .contentModificationDateKey, .attributeModificationDateKey,
      .creationDateKey,
    ]
    let cutoff = Date().addingTimeInterval(-sweepAge)
    let fileManager = FileManager.default
    for folder in sharedFolderURLs() {
      guard
        let files = try? fileManager.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
      else { continue }
      for file in files where sweptExtensions.contains(file.pathExtension.lowercased()) {
        guard let values = try? file.resourceValues(forKeys: Set(keys)),
          values.isRegularFile == true
        else { continue }
        // A copy keeps its original's dates; the attribute (inode) date is the
        // copy's own, so the newest of the three is when it arrived here.
        let newest = [
          values.contentModificationDate, values.attributeModificationDate, values.creationDate,
        ].compactMap { $0 }.max()
        guard let newest, newest < cutoff else { continue }
        try? fileManager.removeItem(at: file)
      }
    }
  }

  // MARK: - Drops

  /// Attaches the drop interaction to the Flutter view once it is in a window:
  /// now if it already is, otherwise when a scene activates or a window
  /// becomes key. Attaches once.
  private func attachDropInteractionWhenReady() {
    if attachDropInteraction() { return }
    let center = NotificationCenter.default
    for name in [UIScene.didActivateNotification, UIWindow.didBecomeKeyNotification] {
      attachObservers.append(
        center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          guard let self, self.attachDropInteraction() else { return }
          self.removeAttachObservers()
        })
    }
  }

  private func removeAttachObservers() {
    for observer in attachObservers { NotificationCenter.default.removeObserver(observer) }
    attachObservers.removeAll()
  }

  /// Returns `true` once the interaction is attached.
  @discardableResult
  private func attachDropInteraction() -> Bool {
    if dropInteractionAttached { return true }
    guard let view = flutterView(), view.window != nil else { return false }
    view.addInteraction(UIDropInteraction(delegate: self))
    dropInteractionAttached = true
    return true
  }

  /// The Flutter view, without forcing a view controller to load its view.
  private func flutterView() -> UIView? {
    if let view = registrar.viewController?.viewIfLoaded { return view }
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    let window = windows.first { $0.isKeyWindow } ?? windows.first
    guard let root = window?.rootViewController as? FlutterViewController else { return nil }
    return root.viewIfLoaded
  }

  func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
    session.hasItemsConforming(toTypeIdentifiers: [UTType.image.identifier])
  }

  func dropInteraction(
    _ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession
  ) -> UIDropProposal {
    UIDropProposal(operation: .copy)
  }

  func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    let providers = session.items.map { $0.itemProvider }
      .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
    guard !providers.isEmpty, let folder = Self.droppedFolderURL() else { return }

    let copies = DropCopies(count: providers.count)
    let group = DispatchGroup()
    for (index, provider) in providers.enumerated() {
      group.enter()
      provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
        // The file is only readable inside this handler, so copy it here.
        let copy = url.flatMap { Self.copyDroppedFile($0, provider: provider, into: folder) }
        copies.set(copy, at: index)
        group.leave()
      }
    }
    group.notify(queue: .main) { [weak self] in
      let paths = copies.paths()
      guard let self, !paths.isEmpty else { return }
      self.channel.invokeMethod("dropped", arguments: paths)
    }
  }

  /// Copies a dropped file to `<folder>/<UUID>.<ext>` and returns its path.
  private static func copyDroppedFile(_ source: URL, provider: NSItemProvider, into folder: URL)
    -> String?
  {
    let destination = folder.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(fileExtension(of: source, provider: provider))
    do {
      try FileManager.default.copyItem(at: source, to: destination)
      return destination.path
    } catch {
      return nil
    }
  }

  private static func fileExtension(of source: URL, provider: NSItemProvider) -> String {
    let fromName = source.pathExtension.lowercased()
    if !fromName.isEmpty { return fromName }
    let fromType = provider.registeredTypeIdentifiers
      .compactMap { UTType($0) }
      .first { $0.conforms(to: .image) }?
      .preferredFilenameExtension
    return fromType ?? "jpg"
  }
}

/// The copies of one drop, filled from the item providers' queues. One slot
/// per photo keeps the drop order; a photo that could not be copied stays nil.
private final class DropCopies {
  private let lock = NSLock()
  private var slots: [String?]

  init(count: Int) { slots = [String?](repeating: nil, count: count) }

  func set(_ path: String?, at index: Int) {
    lock.lock()
    defer { lock.unlock() }
    slots[index] = path
  }

  func paths() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return slots.compactMap { $0 }
  }
}
