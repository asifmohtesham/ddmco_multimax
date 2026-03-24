import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';

/// Session defaults sheet — retains StatefulWidget because it manages
/// transient local UI state (dropdowns, sliders) that belongs to the
/// widget tree, not app state. Sanctioned exception per refactor plan.
class SessionDefaultsBottomSheet extends StatefulWidget {
  const SessionDefaultsBottomSheet({super.key});

  @override
  State<SessionDefaultsBottomSheet> createState() =>
      _SessionDefaultsBottomSheetState();
}

class _SessionDefaultsBottomSheetState
    extends State<SessionDefaultsBottomSheet> {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();
  final StorageService _storageService = Get.find<StorageService>();

  bool _isLoading = true;
  List<String> _companies = [];
  String? _selectedCompany;
  bool _autoSubmitEnabled = true;
  double _autoSubmitDelay = 2.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final companies = await _apiProvider.getList('Company');
      final savedCompany = _storageService.getCompany();
      final autoSubmit = _storageService.getAutoSubmitEnabled();
      final delay = _storageService.getAutoSubmitDelay();

      if (mounted) {
        setState(() {
          _companies = companies;
          _selectedCompany = savedCompany;
          _autoSubmitEnabled = autoSubmit;
          _autoSubmitDelay = delay.toDouble();
          _isLoading = false;
        });
        if (_companies.length == 1 && _selectedCompany == null) {
          setState(() => _selectedCompany = _companies.first);
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotification.error('Failed to load defaults data');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveDefaults() async {
    if (_selectedCompany == null) {
      AppNotification.warning('Company is mandatory.');
      return;
    }
    await _storageService.saveSessionDefaults(_selectedCompany!);
    await _storageService.saveAutoSubmitSettings(
        _autoSubmitEnabled, _autoSubmitDelay.toInt());
    // Use widget's own BuildContext — always valid inside mounted State.
    if (mounted) Navigator.of(context).pop();
    AppNotification.success('Settings Saved');
  }

  Future<void> _reloadPermissions() async {
    setState(() => _isLoading = true);
    try {
      Get.find<PermissionService>().clearCache();
      await Get.find<AuthenticationController>().fetchUserDetails();
      if (mounted) {
        AppNotification.success('Permissions & Roles Reloaded');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        AppNotification.error('Failed to reload permissions: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Settings & Defaults',
                      style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    // Widget context — safe, no GetX overlay involved.
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Session Defaults',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedCompany,
                      decoration: const InputDecoration(
                          labelText: 'Company',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.business)),
                      items: _companies
                          .map((c) => DropdownMenuItem(
                              value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedCompany = val),
                    ),
                    const SizedBox(height: 24),
                    Text('Automation',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor)),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Auto-Submit Valid Items'),
                      subtitle: const Text(
                          'Automatically add item when validation passes'),
                      contentPadding: EdgeInsets.zero,
                      value: _autoSubmitEnabled,
                      onChanged: (val) =>
                          setState(() => _autoSubmitEnabled = val),
                    ),
                    if (_autoSubmitEnabled) ...[
                      const SizedBox(height: 8),
                      Text(
                          'Auto-Submit Delay: ${_autoSubmitDelay.toInt()}s'),
                      Slider(
                        value: _autoSubmitDelay,
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: '${_autoSubmitDelay.toInt()}s',
                        onChanged: (val) =>
                            setState(() => _autoSubmitDelay = val),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text('Troubleshooting',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor)),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            shape: BoxShape.circle),
                        child: Icon(Icons.sync_lock,
                            color: Colors.orange.shade700),
                      ),
                      title: const Text('Reload Permissions'),
                      subtitle: const Text(
                          'Clear cache and re-fetch access rights'),
                      onTap: _reloadPermissions,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveDefaults,
                        style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16)),
                        child: const Text('Save Settings'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
