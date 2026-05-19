import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_navigator.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class ConnectToInstanceController extends GetxController {
  final DatabaseService _dbService = Get.find<DatabaseService>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final DataWedgeService _dataWedge = Get.find<DataWedgeService>();

  final TextEditingController serverUrlController = TextEditingController();
  String currentServerUrl = '';
  final recentUrls = <String>[].obs;
  final isCheckingConnection = false.obs;

  Worker? _scanWorker;
  late final Dio _pingDio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)));

  // ── URL utilities ─────────────────────────────────────────────────────────

  static String normaliseUrl(String raw) {
    String url = raw.trim();
    if (url.isEmpty) return '';
    if (!url.startsWith('http')) url = 'https://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static bool looksLikeUrl(String value) {
    if (value.isEmpty) return false;
    return value.startsWith('http') || value.contains('.');
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void onInit() {
    super.onInit();
    _loadSavedData();
    _scanWorker = ever(_dataWedge.scannedCode, _onHardwareScan);
  }

  Future<void> _loadSavedData() async {
    final savedUrl = await _dbService.getConfig(DatabaseService.serverUrlKey);
    final targetUrl = savedUrl ?? ApiProvider.defaultBaseUrl;
    serverUrlController.text = targetUrl;
    currentServerUrl = targetUrl;
    final urls = await _dbService.getServerUrls();
    recentUrls.assignAll(urls);
    update();
  }

  @override
  void onClose() {
    _scanWorker?.dispose();
    _pingDio.close(force: true);
    // serverUrlController is intentionally not disposed here: Get.delete fires
    // when Navigator.pop() is called, but the sheet's dismiss animation is
    // still running — disposing the controller while TextField is in the tree
    // causes "used after disposal" assertion errors. The TextEditingController
    // is released naturally once _EditableTextState.dispose() completes.
    super.onClose();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  void fillUrl(String url) {
    serverUrlController.text = url;
    serverUrlController.selection = TextSelection.fromPosition(
      TextPosition(offset: url.length),
    );
  }

  Future<void> removeRecentUrl(String url) async {
    await _dbService.removeServerUrl(url);
    recentUrls.remove(url);
  }

  Future<void> saveServerConfiguration() async {
    final rawUrl = serverUrlController.text;
    if (rawUrl.trim().isEmpty) {
      GlobalSnackbar.error(message: 'Server URL cannot be empty');
      return;
    }

    final url = normaliseUrl(rawUrl);

    isCheckingConnection.value = true;
    update();
    // Track whether we navigated away so the finally block skips reactive
    // updates that would try to find a already-deleted controller.
    bool navigatedAway = false;
    try {
      final response = await _pingDio.get('$url/api/method/ping');

      if (response.statusCode == 200) {
        await _confirmAndSave(url);
        navigatedAway = true;
        GlobalSnackbar.success(
          title: 'Connected',
          message: 'Successfully connected to $url',
        );
      } else {
        throw Exception('Invalid response (Status: ${response.statusCode})');
      }
    } catch (e) {
      Get.dialog(
        AlertDialog(
          title: const Text('Connection Failed'),
          content: Text(
            'Could not verify connection to the server.\n\n'
            'Error: $e\n\n'
            'Do you want to save this URL anyway?',
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Get.back();
                await _confirmAndSave(url);
                GlobalSnackbar.success(
                  title: 'Saved',
                  message: 'Server URL saved (Validation skipped)',
                );
              },
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );
    } finally {
      if (!navigatedAway) {
        isCheckingConnection.value = false;
        update();
      }
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  void _onHardwareScan(String value) {
    if (looksLikeUrl(value)) fillUrl(value);
  }

  Future<void> _confirmAndSave(String url) async {
    await _dbService.saveConfig(DatabaseService.serverUrlKey, url);
    await _dbService.saveServerUrl(url);
    serverUrlController.text = url;
    currentServerUrl = url;
    _apiProvider.setBaseUrl(url);
    final urls = await _dbService.getServerUrls();
    recentUrls.assignAll(urls);
    AppNavigator.pop();
  }
}
