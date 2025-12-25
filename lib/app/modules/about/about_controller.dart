import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';

enum IntegrationState { loading, connected, error, offline }

class SystemIntegration {
  final String name;
  final String type;
  IntegrationState state;
  String? details;
  String? latency;
  String? filePath; // Added field for file paths

  SystemIntegration({
    required this.name,
    required this.type,
    this.state = IntegrationState.loading,
    this.details,
    this.latency,
    this.filePath,
  });
}

class AboutController extends GetxController {
  // Application Meta
  final RxString appName = ''.obs;
  final RxString version = ''.obs;
  final RxString buildNumber = ''.obs;

  // Dynamic System Status
  final RxList<SystemIntegration> systemStatus = <SystemIntegration>[].obs;
  final RxBool isCheckingHealth = true.obs;

  @override
  void onInit() {
    super.onInit();
    _loadPackageInfo();
    runHealthChecks();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      appName.value = info.appName;
      version.value = info.version;
      buildNumber.value = info.buildNumber;
    } catch (e) {
      // Fallback
      appName.value = 'ERP';
    }
  }

  /// Real-world technique: Parallel execution of independent health checks
  Future<void> runHealthChecks() async {
    isCheckingHealth.value = true;

    // Initialise placeholders
    systemStatus.assignAll([
      SystemIntegration(name: 'ERP', type: 'Core Backend'),
      SystemIntegration(name: 'SQLite Database', type: 'Config Storage'),
      SystemIntegration(name: 'Zebra DataWedge', type: 'Hardware Scanner'),
    ]);

    // Execute checks in parallel
    await Future.wait([
      _checkApiStatus(0),
      _checkDatabaseStatus(1),
      _checkScannerStatus(2),
    ]);

    isCheckingHealth.value = false;
  }

  Future<void> _checkApiStatus(int index) async {
    final start = DateTime.now();
    try {
      final api = Get.find<ApiProvider>();
      // Fix: Use callMethod instead of .get() which is not exposed
      final response = await api.callMethod('ping');

      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final statusItem = systemStatus[index];

      // Fix: Use Dio's statusCode instead of GetConnect's status.hasError
      if (response.statusCode == 200) {
        statusItem.state = IntegrationState.connected;
        statusItem.details = 'Server Online';
        statusItem.latency = '${elapsed}ms';
      } else {
        statusItem.state = IntegrationState.error;
        statusItem.details = 'Status: ${response.statusCode}';
      }
    } catch (e) {
      systemStatus[index].state = IntegrationState.offline;
      systemStatus[index].details = 'Unreachable';
    }
    systemStatus.refresh();
  }

  Future<void> _checkDatabaseStatus(int index) async {
    try {
      final dbService = Get.find<DatabaseService>();

      // Fix: 'db' is private. We verify health by attempting to read a config key.
      // This confirms the database is open and queryable.
      await dbService.getConfig(DatabaseService.serverUrlKey);

      systemStatus[index].state = IntegrationState.connected;
      systemStatus[index].details = 'Active';
      systemStatus[index].filePath = dbService.dbPath;
    } catch (e) {
      systemStatus[index].state = IntegrationState.error;
      systemStatus[index].details = 'Unavailable';
    }
    systemStatus.refresh();
  }

  Future<void> _checkScannerStatus(int index) async {
    try {
      if (Get.isRegistered<DataWedgeService>()) {
        final dw = Get.find<DataWedgeService>();

        // Dynamic API call to native layer
        final version = await dw.getVersion();

        systemStatus[index].state = IntegrationState.connected;

        if (version != 'Unavailable') {
          systemStatus[index].details = 'DataWedge v$version';
        } else {
          // Fallback for Netum/Generic scanners
          systemStatus[index].details = 'Standard Android Intent';
        }
      } else {
        systemStatus[index].state = IntegrationState.offline;
        systemStatus[index].details = 'Not Registered';
      }
    } catch (e) {
      systemStatus[index].state = IntegrationState.error;
      systemStatus[index].details = 'Driver Error';
    }
    systemStatus.refresh();
  }
}