import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:multimax/app/data/providers/stock_sheet_provider.dart';
import 'package:multimax/app/data/services/native_intake.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/stock_sheet/logic/photo_decoder.dart';
import 'package:multimax/app/modules/stock_sheet/logic/photo_fingerprint.dart';
import 'package:multimax/app/modules/stock_sheet/logic/review_builder.dart';
import 'package:multimax/app/modules/stock_sheet/logic/stock_aggregator.dart';
import 'package:multimax/app/modules/stock_sheet/logic/stock_sheet_codec.dart';
import 'package:multimax/app/modules/stock_sheet/logic/thumbnail_maker.dart';
import 'package:multimax/app/modules/stock_sheet/model/review_models.dart';
import 'package:multimax/app/modules/stock_sheet/model/stock_sheet_models.dart';
import 'package:multimax/app/modules/stock_sheet/output/pdf_stock_sheet_writer.dart';
import 'package:multimax/app/modules/stock_sheet/output/xlsx_stock_sheet_writer.dart';

enum SheetFormat { excel, pdf, both }

enum OutOfStockChoice { includeRed, includePlain, leaveOut }

/// What [StockSheetController.offerShare] did with a new share.
enum ShareOffer {
  /// The share replaced whatever was on screen and is starting.
  started,

  /// Held in [StockSheetController.pendingShare] for the user to decide.
  pending,

  /// Refused: a share is being read and checked, or the sheet built.
  refusedBusy,
}

/// The user's answer to a share held in [StockSheetController.pendingShare].
enum PendingShareChoice { add, startAgain, cancel }

enum StockSheetPhase {
  idle,
  decoding,
  checkingStock,
  reviewing,
  awaitingChoice,
  building,
  done,
  error,
}

/// Saves [bytes] as [fileName] where the user chooses. True when saved, false
/// when the user cancelled; throws when saving failed.
typedef FileSaver = Future<bool> Function(String fileName, Uint8List bytes);

/// Remembers the format of the last Make sheet.
abstract class SheetFormatStore {
  SheetFormat read();
  void write(SheetFormat f);
}

/// [SheetFormatStore] in [StorageService]. A missing or unknown value reads
/// as Excel.
class StorageSheetFormatStore implements SheetFormatStore {
  const StorageSheetFormatStore();

  StorageService get _storage => Get.find<StorageService>();

  @override
  SheetFormat read() =>
      SheetFormat.values.asNameMap()[_storage.getStockSheetFormat()] ??
      SheetFormat.excel;

  @override
  void write(SheetFormat f) => unawaited(
    _storage.saveStockSheetFormat(f.name).catchError((Object e, StackTrace st) {
      // Only the remembered choice is lost; the sheet is still made.
      if (kDebugMode) debugPrint('StockSheetFormatStore: save failed: $e\n$st');
    }),
  );
}

/// Runs one "share photos to a stock sheet" job: decode, check stock, let the
/// user review the photos, ask about out-of-stock items, write the files and
/// share them.
class StockSheetController extends GetxController {
  StockSheetController({
    SheetFormatStore? formatStore,
    PhotoDecoder Function()? decoderFactory,
    StockSheetProvider? provider,
    Future<void> Function(List<XFile>)? shareFiles,
    FileSaver? saveFile,
    DateTime Function()? now,
    Future<Directory> Function()? tempDir,
    Future<Uint8List> Function(StockSheetDocument)? writePdf,
    Future<Uint8List?> Function(String)? makeThumbnail,
    PhotoFingerprinter? fingerprint,
    Future<List<String>> Function()? extraCleanupRoots,
    Future<void> Function()? clearPickerFiles,
  }) : _formatStore = formatStore ?? const StorageSheetFormatStore(),
       _decoderFactory = decoderFactory ?? MlKitPhotoDecoder.new,
       _provider = provider ?? StockSheetProvider(),
       _shareFiles = shareFiles ?? _defaultShare,
       _saveFile = saveFile ?? _defaultSave,
       _now = now ?? DateTime.now,
       _tempDir = tempDir ?? getTemporaryDirectory,
       _writePdf = writePdf ?? PdfStockSheetWriter.writeInBackground,
       _makeThumbnail = makeThumbnail ?? ((path) => ThumbnailMaker.make(path)),
       _fingerprint = fingerprint ?? fingerprintPhotos,
       _clearPickerFiles = clearPickerFiles ?? FilePicker.clearTemporaryFiles,
       _extraCleanupRoots =
           extraCleanupRoots ?? NativeIntake.instance.sharedFolders;

  static const int maxPhotos = 100;
  static const String _title = 'Items';
  static const String _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const String _pdfMime = 'application/pdf';
  static const String shareFailedMessage =
      "Couldn't open the share sheet. Try again.";
  static const String saveFailedMessage = "Couldn't save the file. Try again.";
  static const String noAccessMessage =
      "You don't have access to stock levels.";
  static const String offlineMessage =
      "Couldn't reach the ERP. Check the connection and try again.";
  static const String unsupportedMessage =
      "Reading barcodes from photos isn't supported on this device.";
  static const String notACodeMessage = 'Not a barcode or item code';
  static const String notInErpMessage = 'Not in ERP';
  static const String alreadyListedMessage =
      'Those photos are already in the list.';
  static const String busyMessage =
      'Items from Photos is already generating a file.';
  static const String allOutOfStockMessage =
      'Every photo in the file is out of stock.';

  /// Why photos were refused when only [room] more fit under [maxPhotos].
  static String roomMessage(int room) => switch (room) {
    <= 0 => 'No more photos fit (limit $maxPhotos).',
    1 => 'Only 1 more photo fits (limit $maxPhotos).',
    _ => 'Only $room more photos fit (limit $maxPhotos).',
  };

  static Future<void> _defaultShare(List<XFile> files) async {
    await SharePlus.instance.share(ShareParams(files: files));
  }

  static Future<bool> _defaultSave(String fileName, Uint8List bytes) async {
    final saved = await FilePicker.saveFile(fileName: fileName, bytes: bytes);
    return saved != null;
  }

  final FileSaver _saveFile;

  /// Removes the copies the file picker leaves in the temporary folder
  /// after a save (iOS).
  final Future<void> Function() _clearPickerFiles;
  final SheetFormatStore _formatStore;
  final PhotoDecoder Function() _decoderFactory;
  final StockSheetProvider _provider;
  final Future<void> Function(List<XFile>) _shareFiles;
  final DateTime Function() _now;
  final Future<Directory> Function() _tempDir;
  final Future<Uint8List> Function(StockSheetDocument) _writePdf;
  final Future<Uint8List?> Function(String) _makeThumbnail;
  final PhotoFingerprinter _fingerprint;
  final Future<List<String>> Function() _extraCleanupRoots;

  final busy = false.obs;
  final phase = StockSheetPhase.idle.obs;
  final decoded = 0.obs;
  final total = 0.obs;

  /// The error behind [StockSheetPhase.error]; in
  /// [StockSheetPhase.reviewing], why the last Make sheet failed; in
  /// [StockSheetPhase.done], why Share files did not open the share sheet.
  final errorMessage = RxnString();
  final result = Rxn<StockSheetResult>();
  final files = <XFile>[].obs;
  final thumbnails = <String, Uint8List>{}.obs;

  /// The photos in sheet order, with what was found in each (see
  /// [StockSheetPhase.reviewing]).
  final review = <ReviewEntry>[].obs;

  /// The format offered for Make sheet: the last one used, Excel at first.
  final format = SheetFormat.excel.obs;

  /// True while [shareAgain] is handing the files to the share sheet.
  final sharing = false.obs;

  /// True while [download] saves the files.
  final downloading = false.obs;

  /// True while [fixCode] looks a typed code up.
  final fixing = false.obs;

  /// True while [addPhotos] reads and checks new photos; [decoded] and
  /// [total] then count the new batch.
  final adding = false.obs;

  /// True while [retryCheck] checks an added photo again.
  final rechecking = false.obs;

  /// The photos of the share on screen (see [offerShare]).
  final sharedPaths = <String>[].obs;

  /// Bumped by every share [offerShare] starts, so the screen starts it.
  final shareSerial = 0.obs;

  /// A share that arrived during the review, waiting for
  /// [resolvePendingShare].
  final pendingShare = <String>[].obs;

  /// Bumped when a share held during the review turns out to hold only
  /// photos already in the list, so the screen says so.
  final alreadyListed = 0.obs;

  List<PhotoScan> _scans = const [];

  /// The content fingerprint of every photo that entered the run (review,
  /// being added or held), so a copy under another name is recognised.
  final Map<String, String> _fingerprintOf = {};

  /// The format of the Make sheet in progress.
  SheetFormat _format = SheetFormat.excel;
  final List<File> _created = [];

  /// Every photo path handed to this controller. The share plugin copies
  /// shared photos into the app's cache; [onClose] deletes those copies.
  final Set<String> _givenPhotos = {};

  /// Set by [onClose]. A run still in flight then stops at its next step,
  /// writes and shares nothing, and removes anything it wrote.
  bool _closed = false;

  /// Bumped whenever the review is cleared, so a fix, add or retry that
  /// finishes afterwards does not write into the new review.
  int _generation = 0;

  /// Completes when the [addPhotos] run in flight ends; null when none is.
  Future<void>? _addRun;

  /// The photos the [addPhotos] run in flight is reading and checking.
  List<String> _addingPaths = const [];

  @override
  void onInit() {
    super.onInit();
    format.value = _formatStore.read();
  }

  /// Reads [paths], checks their stock and leaves them in [review].
  /// A photo shared twice is read once.
  Future<void> start(List<String> shared) async {
    _givenPhotos.addAll(shared);
    if (busy.value || _closed) return;
    final paths = shared.toSet().toList();
    busy.value = true;
    try {
      _clear();
      if (paths.length > maxPhotos) {
        errorMessage.value =
            'Share up to $maxPhotos photos at a time (you shared ${paths.length}).';
        phase.value = StockSheetPhase.error;
        return;
      }
      total.value = paths.length;
      phase.value = StockSheetPhase.decoding;
      final unique = await _firstOfEachContent(paths);
      if (_closed) return;
      total.value = unique.length;
      try {
        _scans = await _decode(unique, () => _closed);
      } on UnsupportedError {
        _fail(unsupportedMessage);
        return;
      }
      if (_closed) return;
      await _checkStock();
    } finally {
      busy.value = false;
    }
  }

  /// From [StockSheetPhase.error]: checks stock again without reading the
  /// photos again.
  Future<void> retry() async {
    if (busy.value || _closed || _scans.isEmpty) return;
    if (phase.value != StockSheetPhase.error) return;
    busy.value = true;
    try {
      errorMessage.value = null;
      await _checkStock();
    } finally {
      busy.value = false;
    }
  }

  /// Photos with at least one item switched on.
  int get sheetPhotoCount => ReviewBuilder.sheetPhotoCount(review);

  /// `ReorderableListView` semantics (see [ReviewBuilder.reorder]).
  void reorder(int oldIndex, int newIndex) {
    if (!_reviewing) return;
    review.assignAll(ReviewBuilder.reorder(review, oldIndex, newIndex));
  }

  /// Switches every item of photo [index] on or off.
  void setIncluded(int index, bool on) {
    if (!_reviewing) return;
    review.assignAll(ReviewBuilder.setIncluded(review, index, on));
  }

  /// Switches item [itemIndex] of photo [index] on or off.
  void setItemIncluded(int index, int itemIndex, bool on) {
    if (!_reviewing) return;
    review.assignAll(
      ReviewBuilder.setItemIncluded(review, index, itemIndex, on),
    );
  }

  bool get _reviewing => phase.value == StockSheetPhase.reviewing;

  /// False while a fix, an add, a retry or a run is changing the list, and
  /// outside the review (e.g. while the out-of-stock question is open).
  bool get canRemove =>
      _reviewing &&
      !(adding.value || rechecking.value || fixing.value || busy.value);

  /// Takes photo [index] off the list and returns it, or null when [index]
  /// is out of range or the list is changing. The copy stays on disk, so
  /// [restore] can bring it back; the clean-up at close removes it.
  ReviewEntry? removeAt(int index) {
    if (_closed || !canRemove) return null;
    if (index < 0 || index >= review.length) return null;
    return review.removeAt(index);
  }

  /// Puts a removed [entry] back at [index] (clamped to the list), unless a
  /// photo with its path is listed again.
  void restore(ReviewEntry entry, int index) {
    if (_closed || !_reviewing) return;
    if (review.any((e) => e.path == entry.path)) return;
    // The same photo may have been added again under a new path.
    final print = _fingerprintOf[entry.path];
    if (print != null && review.any((e) => _fingerprintOf[e.path] == print)) {
      return;
    }
    review.insert(index.clamp(0, review.length), entry);
  }

  /// True while a fix, an add or a retry is changing the review.
  bool get _editing => fixing.value || adding.value || rechecking.value;

  /// Looks up [input] (a barcode, a batch QR or a seven-digit item code)
  /// and puts the item on photo [index]. With [noteBarcode] null the item
  /// replaces the photo's items; otherwise it fixes that "Also read" note,
  /// joining the photo's items (an item already there is switched on).
  /// Returns null on success, else the error to show.
  Future<String?> fixCode(
    int index,
    String input, {
    String? noteBarcode,
  }) async {
    if (_closed || fixing.value || busy.value || !_reviewing) return null;
    if (index < 0 || index >= review.length) return null;
    final code = StockSheetCodec.resolveTyped(input);
    if (code == null) return notACodeMessage;
    final entry = review[index];
    final generation = _generation;
    fixing.value = true;
    try {
      final items = await _provider.fetchItems([code.itemCode]);
      if (_stale(generation)) return null;
      final info = items[code.itemCode];
      if (info == null) return notInErpMessage;
      final rows = await _provider.fetchFinishedGoodsStock([code.itemCode]);
      if (_stale(generation)) return null;
      final at = _locate(entry, index);
      if (at < 0) return null;
      final current = review[at];
      final item = ReviewItem(
        code: code,
        info: info,
        stock: StockAggregator.racksByItem(rows)[code.itemCode],
      );
      review[at] = noteBarcode == null
          ? current.copyWith(
              items: [item],
              notInErp: const [],
              typed: true,
              unchecked: false,
            )
          : current.copyWith(
              items: current.items.any((i) => i.code.itemCode == code.itemCode)
                  ? [
                      for (final i in current.items)
                        i.code.itemCode == code.itemCode
                            ? i.copyWith(included: true)
                            : i,
                    ]
                  : [...current.items, item],
              notInErp: [
                for (final b in current.notInErp)
                  if (b != noteBarcode) b,
              ],
              typed: true,
            );
      return null;
    } on StockAccessDenied {
      return noAccessMessage;
    } catch (e, st) {
      _log('code lookup failed', e, st);
      return offlineMessage;
    } finally {
      fixing.value = false;
    }
  }

  /// Free places under [maxPhotos], after the review and the [addPhotos]
  /// run in flight.
  int get photoRoom => math.max(
    0,
    maxPhotos - review.length - (adding.value ? _addingPaths.length : 0),
  );

  /// [paths] once each, without those already in the review or in the
  /// [addPhotos] run in flight. Order kept.
  List<String> _newPhotos(Iterable<String> paths) {
    final listed = {for (final e in review) e.path, ..._addingPaths};
    return [
      for (final path in paths.toSet())
        if (!listed.contains(path)) path,
    ];
  }

  /// Fingerprints [paths] that are not yet known and remembers them.
  Future<void> _fingerprintNew(List<String> paths) async {
    final missing = [
      for (final path in paths)
        if (!_fingerprintOf.containsKey(path)) path,
    ];
    if (missing.isEmpty) return;
    _fingerprintOf.addAll(await _fingerprint(missing));
  }

  /// [paths] without the later copies of a photo whose bytes repeat.
  Future<List<String>> _firstOfEachContent(List<String> paths) async {
    await _fingerprintNew(paths);
    final seen = <String>{};
    return [
      for (final path in paths)
        if (seen.add(_fingerprintOf[path] ?? 'unreadable:$path')) path,
    ];
  }

  /// [paths] whose content is neither in the review, nor being added, nor
  /// held in [pendingShare], nor repeated within [paths]. Order kept.
  Future<List<String>> _newByContent(List<String> paths) async {
    final listed = [
      for (final e in review) e.path,
      ..._addingPaths,
      ...pendingShare,
    ];
    await _fingerprintNew([...paths, ...listed]);
    final checking = paths.toSet();
    final known = <String>{
      for (final path in listed)
        if (!checking.contains(path)) ?_fingerprintOf[path],
    };
    return [
      for (final path in paths)
        if (known.add(_fingerprintOf[path] ?? 'unreadable:$path')) path,
    ];
  }

  /// Reads [paths] (taken, picked or shared during the review) and appends
  /// them to [review], checking stock for their codes only. Photos already
  /// in the list are skipped. Returns null when they were added, else why
  /// none were. If the check fails they are added unchecked, for
  /// [retryCheck].
  Future<String?> addPhotos(List<String> paths) async {
    // Even refused, the share plugin's copies go on close.
    _givenPhotos.addAll(paths);
    if (_closed || busy.value || adding.value || !_reviewing) return null;
    if (paths.isEmpty) return null;
    final generation = _generation;
    final byPath = _newPhotos(paths);
    if (byPath.isEmpty) return alreadyListedMessage;
    // Claim the run before the first await, so nothing else starts an add.
    final done = Completer<void>();
    _addRun = done.future;
    // Until the content is known, every photo by path counts as in flight.
    _addingPaths = byPath;
    adding.value = true;
    decoded.value = 0;
    total.value = byPath.length;
    List<String> fresh;
    var failed = false;
    try {
      fresh = await _newByContent(byPath);
    } catch (e, st) {
      _log('fingerprinting failed', e, st);
      fresh = const [];
      failed = true;
    }
    // Room beside the review, not counting this run's provisional paths.
    _addingPaths = const [];
    final room = photoRoom;
    if (failed || _stale(generation) || fresh.isEmpty || fresh.length > room) {
      _addRun = null;
      adding.value = false;
      done.complete();
      if (_stale(generation)) return null;
      if (failed) return offlineMessage;
      return fresh.isEmpty ? alreadyListedMessage : roomMessage(room);
    }
    _addingPaths = fresh;
    decoded.value = 0;
    total.value = fresh.length;
    try {
      final List<PhotoScan> scans;
      try {
        scans = await _decode(fresh, () => _stale(generation));
      } on UnsupportedError {
        return unsupportedMessage;
      }
      if (_stale(generation)) return null;
      final checked = await _checkScans(scans);
      if (_stale(generation)) return null;
      review.addAll(
        checked ??
            [
              for (final scan in scans)
                scan.items.isEmpty
                    ? ReviewBuilder.entryFor(scan, const {}, const {})
                    : ReviewEntry(
                        path: scan.path,
                        rawValues: scan.rawValues,
                        unchecked: true,
                      ),
            ],
      );
      return null;
    } finally {
      _addingPaths = const [];
      _addRun = null;
      adding.value = false;
      done.complete();
    }
  }

  /// Waits until no [addPhotos] run is in flight.
  Future<void> _addsSettled() async {
    while (_addRun != null) {
      await _addRun;
    }
  }

  /// Checks the stock of added photo [index] again after a failed check,
  /// from the codes already read from it. Returns null when checked (or
  /// when there was nothing to do), else why the check failed.
  Future<String?> retryCheck(int index) async {
    if (_closed || busy.value || rechecking.value || !_reviewing) return null;
    if (index < 0 || index >= review.length) return null;
    final entry = review[index];
    if (!entry.unchecked) return null;
    final generation = _generation;
    rechecking.value = true;
    try {
      final scan = PhotoScan(
        index: index,
        path: entry.path,
        rawValues: entry.rawValues,
        items: StockSheetCodec.itemsInPhoto(entry.rawValues),
      );
      final List<ReviewEntry> checked;
      try {
        checked = await _entriesFor([scan]);
      } on StockAccessDenied {
        return _stale(generation) ? null : noAccessMessage;
      } catch (e, st) {
        _log('stock check of an added photo failed', e, st);
        return _stale(generation) ? null : offlineMessage;
      }
      if (_stale(generation)) return null;
      final at = _locate(entry, index);
      // A code typed meanwhile has already resolved the photo; keep it.
      if (at >= 0 && review[at].unchecked) review[at] = checked.single;
      return null;
    } finally {
      rechecking.value = false;
    }
  }

  /// Makes the sheet from [review] in [f], asking about out-of-stock items
  /// first when any switched-on item is out of stock.
  Future<void> makeSheet(SheetFormat f) async {
    if (busy.value || _closed || _editing) return;
    if (!_reviewing || sheetPhotoCount == 0) return;
    busy.value = true;
    try {
      errorMessage.value = null;
      _format = f;
      format.value = f;
      _formatStore.write(f);
      final built = ReviewBuilder.toResult(review);
      result.value = built;
      if (built.outOfStockCount > 0) {
        phase.value = StockSheetPhase.awaitingChoice;
        return;
      }
      await _build(built.rows, 0, highlight: false, showStatus: false);
    } finally {
      busy.value = false;
    }
  }

  /// Null (the question dismissed) goes back to the review, as does
  /// leaving out the out-of-stock items when nothing else is switched on.
  Future<void> chooseOutOfStock(OutOfStockChoice? choice) async {
    if (busy.value || _closed) return;
    if (phase.value != StockSheetPhase.awaitingChoice) return;
    final current = result.value;
    if (choice == null || current == null) {
      result.value = null;
      phase.value = StockSheetPhase.reviewing;
      return;
    }
    final leaveOut = choice == OutOfStockChoice.leaveOut;
    final rows = leaveOut
        ? current.rows.where((r) => !r.outOfStock).toList()
        : current.rows;
    if (rows.isEmpty) {
      _backToReview(allOutOfStockMessage);
      return;
    }
    busy.value = true;
    try {
      await _build(
        rows,
        leaveOut ? null : current.outOfStockCount,
        highlight: choice == OutOfStockChoice.includeRed,
        showStatus: choice != OutOfStockChoice.leaveOut,
      );
    } finally {
      busy.value = false;
    }
  }

  /// Shares the files already written; the ERP is not asked again.
  Future<void> shareAgain() async {
    if (sharing.value || downloading.value || _closed || files.isEmpty) return;
    sharing.value = true;
    try {
      await _share();
    } finally {
      sharing.value = false;
    }
  }

  /// Saves each file where the user chooses, one dialog per file. Returns
  /// the message to show: what was saved, or [saveFailedMessage]. Null when
  /// the user cancelled (files already saved stay), or when there is nothing
  /// to do or a share or save is already running.
  Future<String?> download() async {
    if (downloading.value || sharing.value || _closed || files.isEmpty) {
      return null;
    }
    downloading.value = true;
    try {
      final names = <String>[];
      for (final file in files.toList()) {
        final bytes = await file.readAsBytes();
        if (!await _saveFile(file.name, bytes)) return null;
        names.add(file.name);
      }
      return names.length == 1
          ? 'Saved ${names.single}.'
          : 'Saved ${names.length} files.';
    } catch (e, st) {
      _log('download failed', e, st);
      return saveFailedMessage;
    } finally {
      downloading.value = false;
    }
  }

  /// True when [retry] can rerun the ERP step: the photos were decoded.
  bool get canRetry => _scans.isNotEmpty;

  /// Takes the photos of a new share. During the review (or its
  /// out-of-stock question), photos being added included, they wait in
  /// [pendingShare] for the user, joining any share already waiting;
  /// otherwise the controller starts over and the screen calls [start] with
  /// [sharedPaths]. Refused, with nothing changed, while a share is being
  /// read and checked or the sheet built.
  ShareOffer offerShare(List<String> paths) {
    // Even refused or held, the share plugin's copies go on close.
    _givenPhotos.addAll(paths);
    if (busy.value) return ShareOffer.refusedBusy;
    if (_reviewing || phase.value == StockSheetPhase.awaitingChoice) {
      unawaited(_holdNew(paths));
      return ShareOffer.pending;
    }
    reset();
    sharedPaths.assignAll(paths);
    shareSerial.value++;
    return ShareOffer.started;
  }

  /// [_hold]s the photos of [paths] whose content is new. When there are
  /// none, bumps [alreadyListed] instead and holds nothing.
  Future<void> _holdNew(List<String> paths) async {
    final generation = _generation;
    try {
      final fresh = await _newByContent(_newPhotos(paths));
      if (_stale(generation)) return;
      if (fresh.isEmpty) {
        alreadyListed.value++;
      } else {
        _hold(fresh);
      }
    } catch (e, st) {
      _log('fingerprinting a held share failed', e, st);
      if (!_stale(generation)) _hold(paths);
    }
  }

  /// Adds [paths] to [pendingShare], each photo once, order kept. Always
  /// notifies, so the screen asks (again) even when nothing changed.
  void _hold(List<String> paths) =>
      pendingShare.assignAll({...pendingShare, ...paths}.toList());

  /// True when the new photos of [pendingShare] fit under [maxPhotos]
  /// beside the review and the photos being added, so it can be added.
  bool get pendingShareFits => _newPhotos(pendingShare).length <= photoRoom;

  /// Acts on the user's answer to [pendingShare]. Ignored while a share is
  /// being read or the sheet built; the share then stays pending. Add and
  /// Start again first wait for photos being added. An Add that no longer
  /// fits once they land is held again, so the user is asked again; for
  /// [PendingShareChoice.add] it otherwise returns why the photos were not
  /// added (as [addPhotos] does); null otherwise.
  Future<String?> resolvePendingShare(PendingShareChoice choice) async {
    if (_closed || pendingShare.isEmpty || busy.value) return null;
    final paths = pendingShare.toList();
    pendingShare.clear();
    switch (choice) {
      case PendingShareChoice.cancel:
        return null;
      case PendingShareChoice.add:
        if (phase.value == StockSheetPhase.awaitingChoice) {
          result.value = null;
          phase.value = StockSheetPhase.reviewing;
        }
        await _addsSettled();
        if (_closed) return null;
        // Another share was started meanwhile.
        if (!_reviewing) return busyMessage;
        final error = await addPhotos(paths);
        if (error != null &&
            !_closed &&
            _reviewing &&
            _newPhotos(paths).length > photoRoom) {
          _hold(paths);
          return null;
        }
        return error;
      case PendingShareChoice.startAgain:
        // The add in flight then stops at its next step, adding nothing.
        _generation++;
        await _addsSettled();
        if (_closed) return null;
        // Another share was started meanwhile.
        if (busy.value) return busyMessage;
        reset();
        sharedPaths.assignAll(paths);
        await start(paths);
        return null;
    }
  }

  /// Back to a blank slate for a new share. Ignored while a run is active.
  void reset() {
    if (busy.value || adding.value) return;
    _clear();
    decoded.value = 0;
    total.value = 0;
    phase.value = StockSheetPhase.idle;
  }

  @override
  void onClose() {
    _closed = true;
    _deleteCreatedFiles();
    unawaited(_deleteSharedCopies(_givenPhotos.toList()));
    _givenPhotos.clear();
    _fingerprintOf.clear();
    unawaited(_clearPickerTemporaryFiles());
    super.onClose();
  }

  Future<void> _clearPickerTemporaryFiles() async {
    try {
      await _clearPickerFiles();
    } catch (e, st) {
      _log('clearing the picker copies failed', e, st);
    }
  }

  void _clear() {
    _generation++;
    _deleteCreatedFiles();
    result.value = null;
    files.clear();
    thumbnails.clear();
    review.clear();
    pendingShare.clear();
    _fingerprintOf.clear();
    errorMessage.value = null;
    _scans = const [];
  }

  /// True once the controller closed or the review was cleared after
  /// [generation] was taken.
  bool _stale(int generation) => _closed || generation != _generation;

  /// Where [entry], last seen at [index], is now: the user may have
  /// reordered or switched rows meanwhile. -1 when it is gone.
  int _locate(ReviewEntry entry, int index) {
    final same = review.indexWhere((e) => identical(e, entry));
    if (same >= 0) return same;
    if (index < review.length && review[index].path == entry.path) {
      return index;
    }
    return review.indexWhere((e) => e.path == entry.path);
  }

  void _deleteCreatedFiles() {
    for (final file in _created) {
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {
        // Best effort: the OS clears the temp folder eventually.
      }
    }
    _created.clear();
  }

  /// Deletes the photos in [paths] that lie inside the app's temporary
  /// (cache) folder or one of the native intake folders (on iOS the App Group,
  /// for a share, and `NSTemporaryDirectory()`, for drops, "Choose files…"
  /// and gallery copies). Anything outside them, such as the gallery original,
  /// is never touched.
  Future<void> _deleteSharedCopies(List<String> paths) async {
    if (paths.isEmpty) return;
    final roots = <String>[];
    try {
      roots.add(p.normalize(p.absolute((await _tempDir()).path)));
    } catch (e, st) {
      _log('temporary folder lookup failed', e, st);
    }
    try {
      for (final folder in await _extraCleanupRoots()) {
        // Native input is not trusted: an empty, relative or filesystem-root
        // folder would make every given path deletable.
        if (folder.isEmpty ||
            !p.isAbsolute(folder) ||
            p.normalize(folder) == p.rootPrefix(folder)) {
          continue;
        }
        roots.add(p.normalize(p.absolute(folder)));
      }
    } catch (e, st) {
      _log('intake folder lookup failed', e, st);
    }
    for (final path in paths) {
      final full = p.normalize(p.absolute(path));
      if (!roots.any((root) => p.isWithin(root, full))) continue;
      try {
        final file = File(full);
        if (await file.exists()) await file.delete();
      } catch (e, st) {
        _log('could not delete $full', e, st);
      }
    }
  }

  void _log(String what, Object e, StackTrace st) {
    if (kDebugMode) debugPrint('StockSheetController: $what: $e\n$st');
  }

  void _fail(String message) {
    errorMessage.value = message;
    phase.value = StockSheetPhase.error;
  }

  /// A failed Make sheet: back to the untouched review, saying why.
  void _backToReview(String message) {
    files.clear();
    _deleteCreatedFiles();
    result.value = null;
    errorMessage.value = message;
    phase.value = StockSheetPhase.reviewing;
  }

  /// Reads every photo in [paths] and makes its thumbnail, stopping once
  /// [abandoned] says so.
  Future<List<PhotoScan>> _decode(
    List<String> paths,
    bool Function() abandoned,
  ) async {
    final decoder = _decoderFactory();
    final scans = <PhotoScan>[];
    try {
      for (var i = 0; i < paths.length; i++) {
        if (abandoned()) break;
        final path = paths[i];
        List<String>? raw;
        try {
          raw = await decoder.decode(path);
        } on UnsupportedError {
          rethrow;
        } catch (e, st) {
          _log('decode failed for $path', e, st);
        }
        if (abandoned()) break;
        scans.add(
          raw == null
              ? PhotoScan(index: i, path: path, decodeFailed: true)
              : PhotoScan(
                  index: i,
                  path: path,
                  rawValues: raw,
                  items: StockSheetCodec.itemsInPhoto(raw),
                ),
        );
        try {
          final thumb = await _makeThumbnail(path);
          if (thumb != null && !abandoned()) thumbnails[path] = thumb;
        } catch (e, st) {
          _log('thumbnail failed for $path', e, st);
        }
        decoded.value = i + 1;
      }
    } finally {
      await decoder.dispose();
    }
    return scans;
  }

  /// The ERP step: items and rack-wise stock, then the review.
  Future<void> _checkStock() async {
    phase.value = StockSheetPhase.checkingStock;
    try {
      final entries = await _entriesFor(_scans);
      if (_closed) return;
      review.assignAll(entries);
      phase.value = StockSheetPhase.reviewing;
    } on StockAccessDenied {
      _fail(noAccessMessage);
    } catch (e, st) {
      _log('stock check failed', e, st);
      _fail(offlineMessage);
    }
  }

  /// Review entries for [scans], from one Item call and one stock call for
  /// their codes. Throws what the provider throws.
  Future<List<ReviewEntry>> _entriesFor(List<PhotoScan> scans) async {
    final codes = <String>{
      for (final scan in scans)
        for (final item in scan.items) item.itemCode,
    }.toList();
    final items = codes.isEmpty
        ? <String, ItemInfo>{}
        : await _provider.fetchItems(codes);
    if (_closed) return const [];
    final stockRows = codes.isEmpty
        ? <Map<String, dynamic>>[]
        : await _provider.fetchFinishedGoodsStock(codes);
    final stock = StockAggregator.racksByItem(stockRows);
    return [
      for (final scan in scans) ReviewBuilder.entryFor(scan, items, stock),
    ];
  }

  /// [_entriesFor] for photos added during the review: null when the check
  /// failed (403 included), so the caller keeps them unchecked.
  Future<List<ReviewEntry>?> _checkScans(List<PhotoScan> scans) async {
    try {
      return await _entriesFor(scans);
    } catch (e, st) {
      _log('stock check of added photos failed', e, st);
      return null;
    }
  }

  /// [outOfStockCount] is null when the out-of-stock rows were left out, so
  /// the subtitle does not count rows the file does not have. A failure to
  /// write or share goes back to the review.
  Future<void> _build(
    List<StockSheetRow> rows,
    int? outOfStockCount, {
    required bool highlight,
    required bool showStatus,
  }) async {
    phase.value = StockSheetPhase.building;
    try {
      final now = _now();
      final subtitle = [
        DateFormat('dd/MM/yyyy HH:mm').format(now),
        _count(sheetPhotoCount, 'photo'),
        _count(rows.length, 'item'),
        if (outOfStockCount != null) '$outOfStockCount out of stock',
      ].join(' · ');
      final doc = StockSheetDocument(
        title: _title,
        subtitle: subtitle,
        rows: rows,
        thumbnails: Map<String, Uint8List>.of(thumbnails),
        highlightOutOfStock: highlight,
        showStatus: showStatus,
      );
      files.clear();
      _deleteCreatedFiles();
      if (rows.isNotEmpty) {
        final dir = await _tempDir();
        if (_abandonIfClosed()) return;
        final stamp = DateFormat('yyyyMMdd-HHmm').format(now);
        if (_format != SheetFormat.pdf) {
          final bytes = await XlsxStockSheetWriter.writeInBackground(doc);
          if (_abandonIfClosed()) return;
          files.add(await _store(dir, 'Items-$stamp.xlsx', bytes, _xlsxMime));
          if (_abandonIfClosed()) return;
        }
        if (_format != SheetFormat.excel) {
          final bytes = await _writePdf(doc);
          if (_abandonIfClosed()) return;
          files.add(await _store(dir, 'Items-$stamp.pdf', bytes, _pdfMime));
          if (_abandonIfClosed()) return;
        }
      }
    } catch (e, st) {
      if (_abandonIfClosed()) return;
      _log('build failed', e, st);
      _backToReview("Couldn't build the sheet. Try again.");
      return;
    }
    if (files.isNotEmpty && !await _share()) {
      _backToReview(shareFailedMessage);
      return;
    }
    phase.value = StockSheetPhase.done;
  }

  /// Hands [files] to the share sheet. A failure keeps the files and says so
  /// through [errorMessage]; returns false then.
  Future<bool> _share() async {
    errorMessage.value = null;
    try {
      await _shareFiles(files.toList());
      return true;
    } catch (e, st) {
      _log('share failed', e, st);
      errorMessage.value = shareFailedMessage;
      return false;
    }
  }

  static String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

  /// After [onClose], removes what this run wrote and tells it to stop.
  bool _abandonIfClosed() {
    if (!_closed) return false;
    files.clear();
    _deleteCreatedFiles();
    return true;
  }

  Future<XFile> _store(
    Directory dir,
    String name,
    Uint8List bytes,
    String mime,
  ) async {
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    _created.add(file);
    return XFile(file.path, mimeType: mime, name: name);
  }
}
