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

  /// The photos are being fingerprinted; the review opens once they are.
  decoding,
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

/// Runs one "share photos to a stock sheet" job: open the review with a row
/// per photo, read the photos and check their stock while the user reviews
/// them, ask about out-of-stock items, write the files and share them.
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
    Future<Uint8List?> Function(String url)? itemThumbnail,
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
       _itemThumbnailOverride = itemThumbnail,
       _fingerprint = fingerprint ?? fingerprintPhotos,
       _clearPickerFiles = clearPickerFiles ?? FilePicker.clearTemporaryFiles,
       _extraCleanupRoots =
           extraCleanupRoots ?? NativeIntake.instance.sharedFolders {
    _readingWatch = review.listen(
      (list) => reading.value = list.any((e) => !e.settled),
    );
  }

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

  /// Downloads an Item's ERP image and makes its thumbnail; null to use
  /// [_defaultItemThumbnail].
  final Future<Uint8List?> Function(String url)? _itemThumbnailOverride;
  final PhotoFingerprinter _fingerprint;
  final Future<List<String>> Function() _extraCleanupRoots;

  /// True while the photos of [start] are fingerprinted.
  final busy = false.obs;

  /// True while any row of [review] is not settled.
  final reading = false.obs;
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

  /// True while [addPhotos] fingerprints new photos; they are then listed
  /// and read with the others.
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

  /// Keeps [reading] in step with [review].
  late final StreamSubscription<List<ReviewEntry>> _readingWatch;

  /// The one decoder, made on first use and disposed with the controller.
  PhotoDecoder? _decoderInstance;
  PhotoDecoder get _decoder => _decoderInstance ??= _decoderFactory();

  /// True while [_pump] runs, so it never runs twice at once.
  bool _pumping = false;

  /// The zoom the reading loop has in hand, if any.
  _ZoomAttempt? _zoomInHand;

  /// Item codes whose Item and stock have been asked for and answered, for
  /// the life of the screen; [_itemsByCode] and [_stockByCode] hold the
  /// answers (a code the ERP does not know, or with no stock, has none).
  final Set<String> _knownCodes = {};
  final Map<String, ItemInfo> _itemsByCode = {};
  final Map<String, ItemStock> _stockByCode = {};

  /// Item codes asked for by a [_requestStock] still in flight.
  final Set<String> _askingCodes = {};

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

  /// The photos the [addPhotos] run in flight is fingerprinting.
  List<String> _addingPaths = const [];

  @override
  void onInit() {
    super.onInit();
    format.value = _formatStore.read();
  }

  /// Fingerprints [shared], opens the review with one "Not read yet" row
  /// per photo and starts reading them (see [_pump]); returns once the
  /// review is open. A photo shared twice, or under two names, is listed
  /// once.
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
      final first = _nextNumber();
      review.assignAll([
        for (var i = 0; i < unique.length; i++)
          ReviewEntry(
            path: unique[i],
            number: first + i,
            stage: ReadStage.notRead,
          ),
      ]);
      phase.value = StockSheetPhase.reviewing;
      unawaited(_pump(_generation));
    } finally {
      busy.value = false;
    }
  }

  /// From [StockSheetPhase.error]: asks for the stock of the rows not yet
  /// settled again, without reading the photos again.
  Future<void> retry() async {
    if (busy.value || _closed || !canRetry) return;
    if (phase.value != StockSheetPhase.error) return;
    errorMessage.value = null;
    phase.value = StockSheetPhase.reviewing;
    await _requestStock();
  }

  /// Photos with at least one item switched on.
  int get sheetPhotoCount => ReviewBuilder.sheetPhotoCount(review);

  /// Items switched on: the rows the file will have.
  int get sheetItemCount => ReviewBuilder.sheetItemCount(review);

  /// Distinct photos in the review (a photo of several items gives several
  /// rows).
  int get photoCount => ReviewBuilder.photoCount(review);

  /// `ReorderableListView` semantics (see [ReviewBuilder.reorder]).
  void reorder(int oldIndex, int newIndex) {
    if (!_reviewing) return;
    review.assignAll(ReviewBuilder.reorder(review, oldIndex, newIndex));
  }

  /// Switches row [index] on or off.
  void setIncluded(int index, bool on) {
    if (!_reviewing) return;
    review.assignAll(ReviewBuilder.setIncluded(review, index, on));
  }

  bool get _reviewing => phase.value == StockSheetPhase.reviewing;

  /// False while a fix, a retry or a run is changing the list, and outside
  /// the review (e.g. while the out-of-stock question is open). Photos being
  /// read or added do not block it.
  bool get canRemove =>
      _reviewing && !(rechecking.value || fixing.value || busy.value);

  /// Takes photo [index] off the list and returns it, or null when [index]
  /// is out of range or the list is changing. A photo not yet read is not
  /// read; the zoom of a photo being zoomed in on is stopped. The copy stays
  /// on disk, so [restore] can bring it back; the clean-up at close removes
  /// it.
  ReviewEntry? removeAt(int index) {
    if (_closed || !canRemove) return null;
    if (index < 0 || index >= review.length) return null;
    final removed = review.removeAt(index);
    final zoom = _zoomInHand;
    if (removed.stage == ReadStage.zooming && zoom?.path == removed.path) {
      zoom!.stopped = true;
    }
    return removed;
  }

  /// Puts a removed [entry] back at [index] (clamped to the list), unless
  /// the row is listed again, or its photo was added again under another
  /// path (the photo's other rows, which share its path, do not count). A
  /// photo whose read was cut short waits to be read afresh: "Not read yet"
  /// before its quick pass, "Waiting to zoom in" after it.
  void restore(ReviewEntry entry, int index) {
    if (_closed || !_reviewing) return;
    if (review.any((e) => e.id == entry.id)) return;
    final print = _fingerprintOf[entry.path];
    if (print != null &&
        review.any(
          (e) => e.path != entry.path && _fingerprintOf[e.path] == print,
        )) {
      return;
    }
    final back = switch (entry.stage) {
      ReadStage.reading => entry.copyWith(stage: ReadStage.notRead),
      ReadStage.zooming => entry.copyWith(stage: ReadStage.waiting),
      _ => entry,
    };
    review.insert(index.clamp(0, review.length), back);
    unawaited(_pump(_generation));
    unawaited(_requestStock());
  }

  /// True while a fix, an add or a retry is changing the review.
  bool get _editing => fixing.value || adding.value || rechecking.value;

  /// Looks up [input] (a barcode, a batch QR or a seven-digit item code)
  /// and makes row [index] that item. Returns null on success, else the
  /// error to show.
  Future<String?> fixCode(int index, String input) async {
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
      final images = _loadItemImages([info]);
      final rows = await _provider.fetchFinishedGoodsStock([code.itemCode]);
      await images;
      if (_stale(generation)) return null;
      final at = _locate(entry, index);
      if (at < 0) return null;
      final item = ReviewItem(
        code: code,
        info: info,
        stock: StockAggregator.racksByItem(rows)[code.itemCode],
      );
      review[at] = review[at].copyWith(
        items: [item],
        notInErp: const [],
        typed: true,
        unchecked: false,
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
    maxPhotos - photoCount - (adding.value ? _addingPaths.length : 0),
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

  /// Appends [paths] (taken, picked or shared during the review) to
  /// [review] as "Not read yet" rows, which join the reading (see [_pump]).
  /// Photos already in the list are skipped. Returns null once they are
  /// listed, without waiting for them to be read, else why none were.
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
    try {
      final List<String> fresh;
      try {
        fresh = await _newByContent(byPath);
      } catch (e, st) {
        _log('fingerprinting failed', e, st);
        return _stale(generation) ? null : offlineMessage;
      }
      if (_stale(generation)) return null;
      if (fresh.isEmpty) return alreadyListedMessage;
      // Room beside the review, not counting this run's provisional paths.
      _addingPaths = const [];
      final room = photoRoom;
      if (fresh.length > room) return roomMessage(room);
      final first = _nextNumber();
      review.addAll([
        for (var i = 0; i < fresh.length; i++)
          ReviewEntry(
            path: fresh[i],
            number: first + i,
            stage: ReadStage.notRead,
          ),
      ]);
      unawaited(_pump(generation));
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
      // Otherwise the photo becomes its rows, one per item.
      if (at >= 0 && review[at].unchecked) {
        review.replaceRange(at, at + 1, _numbered(checked, review[at].number));
      }
      return null;
    } finally {
      rechecking.value = false;
    }
  }

  /// Makes the sheet from [review] in [f], asking about out-of-stock items
  /// first when any switched-on item is out of stock. Does nothing while
  /// photos are being read.
  Future<void> makeSheet(SheetFormat f) async {
    if (busy.value || _closed || _editing || reading.value) return;
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

  /// True when [retry] can rerun the ERP step: rows wait for their stock.
  bool get canRetry => review.any((e) => e.stage == ReadStage.checkingStock);

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
    _generation++;
    unawaited(_readingWatch.cancel());
    // A read in flight finishes first; the reading loop then disposes it.
    if (!_pumping) unawaited(_disposeDecoder());
    _deleteCreatedFiles();
    unawaited(_deleteSharedCopies(_givenPhotos.toList()));
    _givenPhotos.clear();
    _fingerprintOf.clear();
    unawaited(_clearPickerTemporaryFiles());
    super.onClose();
  }

  Future<void> _disposeDecoder() async {
    final decoder = _decoderInstance;
    if (decoder == null) return;
    try {
      await decoder.dispose();
    } catch (e, st) {
      _log('disposing the decoder failed', e, st);
    }
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
  }

  /// True once the controller closed or the review was cleared after
  /// [generation] was taken.
  bool _stale(int generation) => _closed || generation != _generation;

  /// Where [entry], last seen at [index], is now: the user may have
  /// reordered or switched rows meanwhile. -1 when it is gone.
  int _locate(ReviewEntry entry, int index) {
    final same = review.indexWhere((e) => identical(e, entry));
    if (same >= 0) return same;
    if (index < review.length && review[index].id == entry.id) {
      return index;
    }
    return review.indexWhere((e) => e.id == entry.id);
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

  /// Puts the thumbnail of photo [path] in [thumbnails], unless [abandoned]
  /// says so by then. Never throws.
  Future<void> _thumbnail(String path, bool Function() abandoned) async {
    try {
      final thumb = await _makeThumbnail(path);
      if (thumb != null && !abandoned()) thumbnails[path] = thumb;
    } catch (e, st) {
      _log('thumbnail failed for $path', e, st);
    }
  }

  /// The number the next photo listed gets: one more than the highest.
  int _nextNumber() =>
      review.fold(0, (highest, e) => math.max(highest, e.number)) + 1;

  /// The reading loop, and the only one: one photo at a time, never two
  /// reads at once. Each turn takes the first "Not read yet" row in list
  /// order (round one, the whole photo), else the first "Waiting to zoom
  /// in" row (round two), else ends. An answer that comes back after the
  /// review was cleared is dropped, and the loop goes on with the list as
  /// it now is. Does nothing when a loop is running or [generation] is
  /// stale.
  Future<void> _pump(int generation) async {
    if (_pumping || _stale(generation)) return;
    _pumping = true;
    try {
      while (!_closed) {
        final current = _generation;
        var at = review.indexWhere((e) => e.stage == ReadStage.notRead);
        if (at >= 0) {
          if (!await _readWhole(current, review[at])) return;
          continue;
        }
        at = review.indexWhere((e) => e.stage == ReadStage.waiting);
        if (at < 0) break;
        if (!await _zoomIn(current, review[at])) return;
      }
    } finally {
      _pumping = false;
      if (_closed) unawaited(_disposeDecoder());
    }
  }

  /// Round one for [entry]: the whole photo, then its thumbnail. False when
  /// reading must stop (the device cannot read barcodes).
  Future<bool> _readWhole(int generation, ReviewEntry entry) async {
    final path = entry.path;
    _replaceRow(entry, [entry.copyWith(stage: ReadStage.reading)]);
    List<String>? whole;
    try {
      whole = await _decoder.readWhole(path);
    } on UnsupportedError {
      if (!_closed) _fail(unsupportedMessage);
      return false;
    } catch (e, st) {
      _log('decode failed for $path', e, st);
    }
    if (_stale(generation)) return true;
    final row = _rowBeing(path, ReadStage.reading);
    if (row != null) _replaceRow(row, [_afterWhole(row, whole)]);
    await _thumbnail(path, () => _stale(generation));
    if (!_stale(generation) &&
        !review.any((e) => e.stage == ReadStage.notRead)) {
      unawaited(_requestStock());
    }
    return true;
  }

  /// [row] once its whole photo gave [whole]: settled when unreadable,
  /// checking stock when it holds one item, else waiting to zoom in.
  ReviewEntry _afterWhole(ReviewEntry row, List<String>? whole) {
    if (whole == null) {
      return row.copyWith(stage: ReadStage.settled, decodeFailed: true);
    }
    return row.copyWith(
      stage: PhotoDecoder.needsZoom(whole)
          ? ReadStage.waiting
          : ReadStage.checkingStock,
      rawValues: whole,
      codes: StockSheetCodec.itemsInPhoto(whole),
    );
  }

  /// Round two for [entry]: tiles, then the 2x copy. A photo that still has
  /// no item is settled as unresolved; otherwise it waits for its stock.
  /// False when reading must stop (the device cannot read barcodes).
  Future<bool> _zoomIn(int generation, ReviewEntry entry) async {
    final path = entry.path;
    _replaceRow(entry, [entry.copyWith(stage: ReadStage.zooming)]);
    final attempt = _zoomInHand = _ZoomAttempt(path);
    List<String>? zoomed;
    try {
      zoomed = await _decoder.zoomIn(
        path,
        whole: entry.rawValues,
        stopped: () => attempt.stopped || _stale(generation),
      );
    } on UnsupportedError {
      if (!_closed) _fail(unsupportedMessage);
      return false;
    } catch (e, st) {
      _log('zooming in failed for $path', e, st);
    } finally {
      if (identical(_zoomInHand, attempt)) _zoomInHand = null;
    }
    // A stopped zoom's answer is thrown away; the photo, if put back, is
    // read afresh.
    if (attempt.stopped || _stale(generation)) return true;
    final row = _rowBeing(path, ReadStage.zooming);
    if (row != null) {
      // Nothing more from the tiles: what the whole photo gave stands.
      final raw = zoomed ?? row.rawValues;
      final codes = StockSheetCodec.itemsInPhoto(raw);
      _replaceRow(
        row,
        codes.isEmpty
            ? _numbered(
                ReviewBuilder.entriesFor(
                  _scanOf(row, rawValues: raw),
                  const {},
                  const {},
                ),
                row.number,
              )
            : [
                row.copyWith(
                  stage: ReadStage.checkingStock,
                  rawValues: raw,
                  codes: codes,
                ),
              ],
      );
    }
    unawaited(_requestStock());
    return true;
  }

  /// The row of photo [path] in [stage], or null when it is gone.
  ReviewEntry? _rowBeing(String path, ReadStage stage) {
    for (final e in review) {
      if (e.path == path && e.stage == stage) return e;
    }
    return null;
  }

  /// Puts [rows] where [row] is, if it is still listed.
  void _replaceRow(ReviewEntry row, List<ReviewEntry> rows) {
    final at = review.indexWhere((e) => identical(e, row));
    if (at >= 0) review.replaceRange(at, at + 1, rows);
  }

  /// [rows] with the photo [number] they came from.
  static List<ReviewEntry> _numbered(List<ReviewEntry> rows, int number) => [
    for (final r in rows) r.copyWith(number: number),
  ];

  /// The read so far of [row]'s photo, for [ReviewBuilder.entriesFor].
  static PhotoScan _scanOf(ReviewEntry row, {List<String>? rawValues}) {
    final raw = rawValues ?? row.rawValues;
    return PhotoScan(
      index: math.max(0, row.number - 1),
      path: row.path,
      rawValues: raw,
      items: rawValues == null ? row.codes : StockSheetCodec.itemsInPhoto(raw),
    );
  }

  /// Asks for the Item and stock of the codes read so far that are neither
  /// known nor already asked for (one Item call and one stock call, ERP
  /// images alongside), then settles every row checking stock whose codes
  /// are all known. A batch that fails leaves its rows "Stock not checked"
  /// (for [retryCheck]); no access to stock levels ends in the error state.
  Future<void> _requestStock() async {
    if (_closed) return;
    _settleKnown();
    if (phase.value == StockSheetPhase.error) return;
    final codes = <String>{
      for (final e in review)
        if (!e.settled)
          for (final code in e.codes)
            if (!_knownCodes.contains(code.itemCode) &&
                !_askingCodes.contains(code.itemCode))
              code.itemCode,
    }.toList();
    if (codes.isEmpty) return;
    final generation = _generation;
    _askingCodes.addAll(codes);
    Object? failure;
    try {
      await _fetchIntoCache(codes);
    } catch (e, st) {
      _log('stock check failed', e, st);
      failure = e;
    } finally {
      _askingCodes.removeAll(codes);
    }
    if (_closed) return;
    if (failure != null && _stale(generation)) {
      // A batch of an earlier review: the rows now listed ask for themselves.
      await _requestStock();
      return;
    }
    if (failure is StockAccessDenied) {
      _fail(noAccessMessage);
    } else if (failure != null) {
      _markUnchecked(codes.toSet());
    }
    _settleKnown();
  }

  /// Replaces every row checking stock whose codes are all known with its
  /// item rows, in place, and loads the ERP images of those items that have
  /// none yet (a review cleared since, or a download that failed).
  void _settleKnown() {
    var changed = false;
    final out = <ReviewEntry>[];
    final infos = <ItemInfo>[];
    for (final e in review) {
      if (e.stage == ReadStage.checkingStock &&
          e.codes.every((c) => _knownCodes.contains(c.itemCode))) {
        final rows = _numbered(
          ReviewBuilder.entriesFor(_scanOf(e), _itemsByCode, _stockByCode),
          e.number,
        );
        out.addAll(rows);
        for (final row in rows) {
          for (final item in row.items) {
            infos.add(item.info);
          }
        }
        changed = true;
      } else {
        out.add(e);
      }
    }
    if (!changed) return;
    review.assignAll(out);
    unawaited(_loadItemImages(infos, generation: _generation));
  }

  /// The rows checking stock for any of [codes], after their batch failed:
  /// settled as "Stock not checked".
  void _markUnchecked(Set<String> codes) {
    var changed = false;
    final out = <ReviewEntry>[];
    for (final e in review) {
      if (e.stage == ReadStage.checkingStock &&
          e.codes.any((c) => codes.contains(c.itemCode))) {
        out.add(
          ReviewEntry(
            path: e.path,
            id: e.id,
            rawValues: e.rawValues,
            unchecked: true,
            number: e.number,
          ),
        );
        changed = true;
      } else {
        out.add(e);
      }
    }
    if (changed) review.assignAll(out);
  }

  /// Asks the ERP for the Item and stock of [codes] and keeps the answers
  /// by item code. Throws what the provider throws.
  Future<void> _fetchIntoCache(List<String> codes) async {
    if (codes.isEmpty) return;
    final items = await _provider.fetchItems(codes);
    if (_closed) return;
    // The ERP images download while the stock is checked.
    final images = _loadItemImages(items.values);
    final stockRows = await _provider.fetchFinishedGoodsStock(codes);
    await images;
    final stock = StockAggregator.racksByItem(stockRows);
    for (final code in codes) {
      _itemsByCode.remove(code);
      _stockByCode.remove(code);
    }
    _itemsByCode.addAll(items);
    _stockByCode.addAll(stock);
    _knownCodes.addAll(codes);
  }

  /// Review entries for [scans], from one Item call and one stock call for
  /// their codes, which are kept by item code too. Throws what the provider
  /// throws.
  Future<List<ReviewEntry>> _entriesFor(List<PhotoScan> scans) async {
    final codes = <String>{
      for (final scan in scans)
        for (final item in scan.items) item.itemCode,
    }.toList();
    await _fetchIntoCache(codes);
    if (_closed) return const [];
    return [
      for (final scan in scans)
        ...ReviewBuilder.entriesFor(scan, _itemsByCode, _stockByCode),
    ];
  }

  /// At most this many ERP images download at once.
  static const int _imageDownloads = 4;

  /// Puts the thumbnail of each Item's ERP image in [thumbnails] under
  /// [ItemInfo.thumbnailKey], skipping Items without an image and those
  /// already there. Never throws: an image that cannot be fetched or read
  /// leaves the row's image blank. With [generation], nothing is written
  /// once the review has been cleared since.
  Future<void> _loadItemImages(
    Iterable<ItemInfo> infos, {
    int? generation,
  }) async {
    bool abandoned() => generation == null ? _closed : _stale(generation);
    final queue = [
      for (final info in infos)
        if (info.image != null &&
            !thumbnails.containsKey(ItemInfo.thumbnailKey(info.itemCode)))
          info,
    ];
    Future<void> worker() async {
      while (queue.isNotEmpty && !abandoned()) {
        final info = queue.removeLast();
        try {
          final thumb = await (_itemThumbnailOverride ?? _defaultItemThumbnail)(
            info.image!,
          );
          if (thumb != null && !abandoned()) {
            thumbnails[ItemInfo.thumbnailKey(info.itemCode)] = thumb;
          }
        } catch (e, st) {
          _log('ERP image of ${info.itemCode} failed', e, st);
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < math.min(_imageDownloads, queue.length); i++)
        worker(),
    ]);
  }

  Future<Uint8List?> _defaultItemThumbnail(String url) async =>
      ThumbnailMaker.fromBytes(await _provider.fetchImage(url));

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
        // The photos the file's rows came from (rows left out not counted).
        _count({for (final r in rows) r.photoPath}.length, 'photo'),
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

/// One zoom by the reading loop. [stopped] is set when its row is removed;
/// it stays with this attempt, so a row put back is zoomed in on afresh.
class _ZoomAttempt {
  _ZoomAttempt(this.path);

  final String path;
  bool stopped = false;
}
