import UIKit
import UniformTypeIdentifiers

/// The Multimax share screen: hands shared photos to the app.
///
/// It replaces `RSIShareViewController` from `receive_sharing_intent`, which
/// hung Finder on the Mac (it accepts a loaded item only as a `URL` or a
/// `UIImage`, ignores anything else and has no time-out). This screen loads
/// every photo as a file, shows a visible card while it works, and always ends:
/// with the app opened, a message, or a cancel.
///
/// It writes the contract the app half of `receive_sharing_intent` 1.9.0 reads
/// (pinned in pubspec.yaml; re-check this file on any upgrade):
/// - group defaults `ShareKey`: JSON array of the plugin's `SharedMediaFile`
///   (`path` = file URL string, percent-decoded; `mimeType`; `type` "image");
/// - the URL `ShareMedia-<host bundle id>:share` opens the app.
/// Beside `ShareKey` it writes `MultimaxShareId`, a UUID per share, so the app
/// (`ios/Runner/IntakeBridge.swift`) can pick a share up on its own when the
/// URL does not open it (seen as a risk on the Mac).
final class ShareViewController: UIViewController {
  // MARK: - Contract

  private static let appGroupIdKey = "AppGroupId"
  private static let defaultGroupId = "group.com.ddmco.multimax"
  private static let defaultHostBundleId = "com.ddmco.multimax"
  private static let shareKey = "ShareKey"
  private static let shareMessageKey = "ShareMessageKey"
  private static let shareIdKey = "MultimaxShareId"
  private static let schemePrefix = "ShareMedia-"

  /// The extensions the app's daily sweep of the App Group deletes; a copy
  /// always gets one of these (IntakeBridge.sweptExtensions).
  private static let copyExtensions: Set<String> = [
    "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "webp",
  ]

  // MARK: - Timing

  /// Long enough for a few cloud (OneDrive) placeholders to download.
  private static let loadTimeout: TimeInterval = 120
  /// How long the app gets to come forward before the card asks the user to
  /// switch to it.
  private static let openWait: TimeInterval = 3
  /// How long "Switch to Multimax to continue." stays before the card closes.
  private static let switchMessageTime: TimeInterval = 2

  // MARK: - Copy

  private static func sendingText(count: Int) -> String {
    count == 1 ? "Sending 1 photo to Multimax…" : "Sending \(count) photos to Multimax…"
  }
  private static let openingText = "Opening Multimax…"
  private static let switchText = "Switch to Multimax to continue."
  private static let unreadableText = "Couldn't read these photos."
  private static let timeoutText =
    "Multimax couldn't get these photos in time. Try fewer, or download them first."

  // MARK: - State (main thread only)

  private enum Phase { case idle, loading, opening, done }
  private var phase = Phase.idle
  private var copies: ShareCopies?
  private var loadProgress: [Progress] = []
  private var timeoutWork: DispatchWorkItem?
  private var hostBackgroundObserver: NSObjectProtocol?

  // MARK: - Card

  private let spinner = UIActivityIndicatorView(style: .medium)
  private let messageLabel = UILabel()
  private let cancelButton = UIButton(type: .system)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    preferredContentSize = CGSize(width: 340, height: 180)

    spinner.color = .secondaryLabel
    spinner.hidesWhenStopped = true
    spinner.startAnimating()

    messageLabel.font = .preferredFont(forTextStyle: .body)
    messageLabel.adjustsFontForContentSizeCategory = true
    messageLabel.textColor = .label
    messageLabel.textAlignment = .center
    messageLabel.numberOfLines = 0
    messageLabel.text = Self.sendingText(count: imageProviders().count)

    cancelButton.setTitle("Cancel", for: .normal)
    cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
    cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
    cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

    let stack = UIStackView(arrangedSubviews: [spinner, messageLabel, cancelButton])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    let margins = view.layoutMarginsGuide
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: margins.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: margins.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: margins.trailingAnchor, constant: -8),
      stack.topAnchor.constraint(greaterThanOrEqualTo: margins.topAnchor),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: margins.bottomAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard phase == .idle else { return }
    startLoading()
  }

  deinit {
    if let hostBackgroundObserver {
      NotificationCenter.default.removeObserver(hostBackgroundObserver)
    }
  }

  // MARK: - Loading

  /// The shared attachments that are images, in the order they were shared.
  private func imageProviders() -> [NSItemProvider] {
    (extensionContext?.inputItems ?? [])
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] }
      .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
  }

  private func startLoading() {
    let providers = imageProviders()
    guard !providers.isEmpty, let container = Self.groupContainerURL() else {
      phase = .done
      showMessageThenCancel(Self.unreadableText)
      return
    }
    phase = .loading
    messageLabel.text = Self.sendingText(count: providers.count)

    let copies = ShareCopies(count: providers.count)
    self.copies = copies
    let group = DispatchGroup()
    for (index, provider) in providers.enumerated() {
      group.enter()
      let typeId = Self.imageTypeIdentifier(of: provider)
      let progress = provider.loadFileRepresentation(forTypeIdentifier: typeId) { url, _ in
        // The file is deleted when this handler returns, so copy it here.
        let copy = url.flatMap {
          Self.copyIntoGroup($0, typeId: typeId, provider: provider, container: container)
        }
        copies.store(copy, at: index)
        group.leave()
      }
      loadProgress.append(progress)
    }

    let timeout = DispatchWorkItem { [weak self] in self?.loadTimedOut() }
    timeoutWork = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadTimeout, execute: timeout)

    group.notify(queue: .main) { [weak self] in self?.loadFinished() }
  }

  private func loadFinished() {
    guard phase == .loading, let copies else { return }
    timeoutWork?.cancel()
    let entries = copies.entries()
    guard !entries.isEmpty, writeShare(entries) else {
      phase = .done
      copies.discard()
      showMessageThenCancel(Self.unreadableText)
      return
    }
    openHostApp()
  }

  private func loadTimedOut() {
    guard phase == .loading else { return }
    phase = .done
    stopLoading()
    showMessageThenCancel(Self.timeoutText)
  }

  @objc private func cancelTapped() {
    guard phase == .idle || phase == .loading else { return }
    phase = .done
    stopLoading()
    cancelRequest()
  }

  /// Stops the loads still running and deletes the copies made so far.
  private func stopLoading() {
    timeoutWork?.cancel()
    copies?.discard()
    for progress in loadProgress { progress.cancel() }
    loadProgress.removeAll()
  }

  // MARK: - Copies

  private static var groupId: String {
    (Bundle.main.object(forInfoDictionaryKey: appGroupIdKey) as? String)
      .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } ?? defaultGroupId
  }

  private static func groupContainerURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
  }

  /// The provider's own image type (most faithful first), so the loaded file
  /// keeps its format; `public.image` when none is registered as such.
  private static func imageTypeIdentifier(of provider: NSItemProvider) -> String {
    provider.registeredTypeIdentifiers.first {
      UTType($0)?.conforms(to: .image) == true
    } ?? UTType.image.identifier
  }

  /// Copies a loaded file to `<App Group>/<UUID>.<ext>`.
  private static func copyIntoGroup(
    _ source: URL, typeId: String, provider: NSItemProvider, container: URL
  ) -> ShareEntry? {
    let ext = fileExtension(of: source, typeId: typeId, provider: provider)
    let destination = container.appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(ext)
    do {
      try FileManager.default.copyItem(at: source, to: destination)
    } catch {
      return nil
    }
    // Decoded: the plugin hands the path to Flutter as it is, with the scheme
    // stripped, and Flutter does not expect percent-encoded file names.
    let path = destination.absoluteString.removingPercentEncoding ?? destination.absoluteString
    return ShareEntry(
      url: destination, path: path,
      mimeType: UTType(filenameExtension: ext)?.preferredMIMEType)
  }

  /// The loaded file's extension when the sweep knows it, otherwise one from
  /// the attachment's image type, otherwise "jpg".
  private static func fileExtension(of source: URL, typeId: String, provider: NSItemProvider)
    -> String
  {
    let fromName = source.pathExtension.lowercased()
    if copyExtensions.contains(fromName) { return fromName }
    let types = [typeId] + provider.registeredTypeIdentifiers
    let fromType = types.lazy
      .compactMap { UTType($0) }
      .filter { $0.conforms(to: .image) }
      .compactMap { $0.preferredFilenameExtension?.lowercased() }
      .first { copyExtensions.contains($0) }
    return fromType ?? "jpg"
  }

  // MARK: - Hand-over

  /// The plugin's `SharedMediaFile` (path, mimeType, thumbnail, duration,
  /// message, type); the fields an image does not use are left out.
  private struct SharedMediaFile: Encodable {
    let path: String
    let mimeType: String?
    let type: String
  }

  /// Writes `ShareKey` and `MultimaxShareId` together; `false` if it cannot.
  private func writeShare(_ entries: [ShareEntry]) -> Bool {
    let files = entries.map { SharedMediaFile(path: $0.path, mimeType: $0.mimeType, type: "image") }
    guard let defaults = UserDefaults(suiteName: Self.groupId),
      let data = try? JSONEncoder().encode(files)
    else { return false }
    defaults.set(data, forKey: Self.shareKey)
    defaults.set(UUID().uuidString, forKey: Self.shareIdKey)
    defaults.removeObject(forKey: Self.shareMessageKey)
    defaults.synchronize()
    return true
  }

  private static var hostBundleId: String {
    guard let id = Bundle.main.bundleIdentifier, let dot = id.lastIndex(of: ".") else {
      return defaultHostBundleId
    }
    return String(id[..<dot])
  }

  /// Opens the app, then closes the card once the host app goes to the
  /// background (the app came forward), or after asking the user to switch.
  private func openHostApp() {
    phase = .opening
    cancelButton.isHidden = true
    messageLabel.text = Self.openingText

    hostBackgroundObserver = NotificationCenter.default.addObserver(
      forName: .NSExtensionHostDidEnterBackground, object: nil, queue: .main
    ) { [weak self] _ in self?.complete() }

    guard let url = URL(string: "\(Self.schemePrefix)\(Self.hostBundleId):share"),
      openURL(url, completion: { [weak self] opened in
        if !opened { DispatchQueue.main.async { self?.askToSwitch() } }
      })
    else {
      askToSwitch()
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.openWait) { [weak self] in
      self?.askToSwitch()
    }
  }

  /// The app will pick the share up when it next becomes active.
  private func askToSwitch() {
    guard phase == .opening else { return }
    phase = .done
    spinner.stopAnimating()
    messageLabel.text = Self.switchText
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.switchMessageTime) { [weak self] in
      self?.completeRequest()
    }
  }

  private func complete() {
    guard phase == .opening else { return }
    phase = .done
    completeRequest()
  }

  /// Walks the responder chain to the `UIApplication` and asks it to open the
  /// URL (`open(_:options:completionHandler:)` from iOS 18, `openURL:` before),
  /// through the Objective-C runtime because extensions may not call it
  /// directly. Returns whether a responder took the request.
  private func openURL(_ url: URL, completion: @escaping (Bool) -> Void) -> Bool {
    var responder: UIResponder? = self
    if #available(iOS 18.0, *) {
      let selector = NSSelectorFromString("openURL:options:completionHandler:")
      while let current = responder {
        if current is UIApplication, current.responds(to: selector) {
          typealias OpenURL = @convention(c) (
            AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
          ) -> Void
          let open = unsafeBitCast(current.method(for: selector), to: OpenURL.self)
          let handler: @convention(block) (Bool) -> Void = { completion($0) }
          open(current, selector, url as NSURL, NSDictionary(), handler)
          return true
        }
        responder = current.next
      }
    } else {
      let selector = NSSelectorFromString("openURL:")
      while let current = responder {
        if current.responds(to: selector) {
          _ = current.perform(selector, with: url)
          return true
        }
        responder = current.next
      }
    }
    return false
  }

  // MARK: - Ending

  private func showMessageThenCancel(_ message: String) {
    spinner.stopAnimating()
    cancelButton.isHidden = true
    messageLabel.text = message
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(
      UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.cancelRequest() })
    present(alert, animated: true)
  }

  private func cancelRequest() {
    extensionContext?.cancelRequest(
      withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
  }

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}

/// One photo copied into the App Group.
private struct ShareEntry {
  let url: URL
  let path: String
  let mimeType: String?
}

/// The copies of one share, filled from the item providers' queues. One slot
/// per photo keeps the shared order; a photo that could not be copied stays
/// nil. Once discarded, it deletes its copies and any that arrive later.
private final class ShareCopies {
  private let lock = NSLock()
  private var slots: [ShareEntry?]
  private var discarded = false

  init(count: Int) { slots = [ShareEntry?](repeating: nil, count: count) }

  func store(_ entry: ShareEntry?, at index: Int) {
    lock.lock()
    let keep = !discarded
    if keep { slots[index] = entry }
    lock.unlock()
    if !keep, let entry { try? FileManager.default.removeItem(at: entry.url) }
  }

  func entries() -> [ShareEntry] {
    lock.lock()
    defer { lock.unlock() }
    return slots.compactMap { $0 }
  }

  func discard() {
    lock.lock()
    discarded = true
    let made = slots.compactMap { $0 }
    slots = slots.map { _ in nil }
    lock.unlock()
    for entry in made { try? FileManager.default.removeItem(at: entry.url) }
  }
}
