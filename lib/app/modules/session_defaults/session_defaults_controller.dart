import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

/// Full-screen replacement for the old Session Defaults bottom sheet.
/// UI-free [persist] is split out so it is unit-testable without GetX overlay.
class SessionDefaultsController extends GetxController {
  final StorageService _storage;
  ApiProvider? _api;

  SessionDefaultsController({StorageService? storage})
      : _storage = storage ?? Get.find<StorageService>();

  ApiProvider get _apiProvider => _api ??= Get.find<ApiProvider>();

  final isLoading = true.obs;
  final isSaving = false.obs;
  final companies = <String>[].obs;
  final selectedCompany = RxnString();
  final autoSubmitEnabled = true.obs;
  final autoSubmitDelay = 1.obs;
  final autoSaveDelay = 5.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    autoSubmitEnabled.value = _storage.getAutoSubmitEnabled();
    autoSubmitDelay.value = _storage.getAutoSubmitDelay();
    autoSaveDelay.value = _storage.getAutoSaveDelay();
    selectedCompany.value =
        _storage.hasSessionDefaults() ? _storage.getCompany() : null;
    try {
      final list = await _apiProvider.getList('Company');
      companies.assignAll(list.map((c) => c['name'] as String));
      if (companies.length == 1 && selectedCompany.value == null) {
        selectedCompany.value = companies.first;
      }
    } catch (_) {
      AppNotification.error('Failed to load companies');
    } finally {
      isLoading.value = false;
    }
  }

  /// Writes current settings to storage. Returns false if no company chosen.
  Future<bool> persist() async {
    final company = selectedCompany.value;
    if (company == null || company.isEmpty) return false;
    await _storage.saveSessionDefaults(company);
    await _storage.saveAutoSubmitSettings(
        autoSubmitEnabled.value, autoSubmitDelay.value);
    await _storage.saveAutoSaveDelay(autoSaveDelay.value);
    return true;
  }

  Future<void> save() async {
    isSaving.value = true;
    final ok = await persist();
    isSaving.value = false;
    if (!ok) {
      AppNotification.warning('Company is required');
      return;
    }
    AppNotification.success('Settings saved');
    Get.back();
  }

  Future<void> reloadPermissions() async {
    try {
      Get.find<PermissionService>().clearCache();
      await Get.find<AuthenticationController>().fetchUserDetails();
      AppNotification.success('Permissions & roles reloaded');
    } catch (e) {
      AppNotification.error('Failed to reload permissions');
    }
  }
}
