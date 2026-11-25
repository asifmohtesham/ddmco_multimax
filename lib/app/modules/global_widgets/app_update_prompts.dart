import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';

enum AppStorePromptResult { deferred, later, update }

class AppUpdatePrompts {
  final messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorObserver = _UpdateNavigatorObserver();
  final _restarting = false.obs;
  ScaffoldFeatureController<MaterialBanner, MaterialBannerClosedReason>?
  _restartBanner;

  NavigatorObserver get navigatorObserver => _navigatorObserver;

  void showRestart(Future<bool> Function() restart) {
    final messenger = messengerKey.currentState;
    if (messenger == null || _restartBanner != null) return;

    late final ScaffoldFeatureController<
      MaterialBanner,
      MaterialBannerClosedReason
    >
    banner;
    banner = messenger.showMaterialBanner(
      MaterialBanner(
        content: const Text('Update downloaded — Restart to install'),
        actions: [
          Obx(
            () => TextButton(
              onPressed: _restarting.value ? null : hideRestart,
              child: const Text('Dismiss'),
            ),
          ),
          Builder(
            builder: (context) => AsyncFilledButton(
              busy: _restarting,
              icon: const Icon(Icons.restart_alt),
              label: 'Restart',
              spinnerColor: Theme.of(context).colorScheme.onSurface,
              onPressed: () async {
                if (_restarting.value || _restartBanner != banner) return;
                _restarting.value = true;
                try {
                  if (await restart() && _restartBanner == banner) {
                    hideRestart();
                  }
                } finally {
                  _restarting.value = false;
                }
              },
            ),
          ),
        ],
      ),
    );
    _restartBanner = banner;
    banner.closed.then((_) {
      if (_restartBanner == banner) _restartBanner = null;
    });
  }

  void hideRestart() {
    if (_restartBanner == null) return;
    _restartBanner = null;
    messengerKey.currentState?.removeCurrentMaterialBanner();
  }

  Future<AppStorePromptResult> showAppStore({
    required String installedVersion,
    required String storeVersion,
    required Future<bool> Function() openStore,
  }) async {
    final navigator = _navigatorObserver.navigator;
    if (navigator == null || !_navigatorObserver.canShowDialog) {
      return AppStorePromptResult.deferred;
    }
    final result = await showDialog<AppStorePromptResult>(
      context: navigator.context,
      builder: (context) => _AppStoreUpdateDialog(
        installedVersion: installedVersion,
        storeVersion: storeVersion,
        openStore: openStore,
      ),
    );
    return result ?? AppStorePromptResult.later;
  }
}

class _UpdateNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? _topRoute;

  // PopupRoute covers GetX, Material, and Cupertino dialogs and modal sheets.
  bool get canShowDialog =>
      _topRoute?.isCurrent == true && _topRoute is! PopupRoute;

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _topRoute = topRoute;
  }
}

class _AppStoreUpdateDialog extends StatefulWidget {
  const _AppStoreUpdateDialog({
    required this.installedVersion,
    required this.storeVersion,
    required this.openStore,
  });

  final String installedVersion;
  final String storeVersion;
  final Future<bool> Function() openStore;

  @override
  State<_AppStoreUpdateDialog> createState() => _AppStoreUpdateDialogState();
}

class _AppStoreUpdateDialogState extends State<_AppStoreUpdateDialog> {
  final _openingStore = false.obs;

  bool get _isCurrent => mounted && ModalRoute.isCurrentOf(context) == true;

  void _later() {
    if (_openingStore.value || !_isCurrent) return;
    Navigator.of(context).pop(AppStorePromptResult.later);
  }

  Future<void> _update() async {
    if (_openingStore.value || !_isCurrent) return;
    _openingStore.value = true;
    try {
      final opened = await widget.openStore();
      if (opened && _isCurrent) {
        Navigator.of(context).pop(AppStorePromptResult.update);
      }
    } finally {
      _openingStore.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Obx(
      () => PopScope(
        canPop: !_openingStore.value,
        child: AlertDialog(
          backgroundColor: colors.surface,
          title: const Text('Update available'),
          content: Text(
            'Multimax ${widget.storeVersion} is on the App Store. '
            'You have ${widget.installedVersion}.',
          ),
          actions: [
            TextButton(
              onPressed: _openingStore.value ? null : _later,
              child: const Text('Later'),
            ),
            AsyncFilledButton(
              busy: _openingStore,
              icon: const Icon(Icons.open_in_new),
              label: 'Update',
              spinnerColor: colors.onSurface,
              onPressed: _update,
            ),
          ],
        ),
      ),
    );
  }
}
