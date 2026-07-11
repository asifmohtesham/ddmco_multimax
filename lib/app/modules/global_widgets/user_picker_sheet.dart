import 'package:flutter/material.dart';
import 'package:multimax/app/data/models/user_model.dart';

/// A reusable user-picker bottom sheet, mirroring [WarehousePickerSheet].
///
/// Usage:
///
/// ```dart
/// Get.bottomSheet(
///   UserPickerSheet(
///     users: users,
///     isLoading: isFetchingUsers,
///     onSelected: (userId, displayName) { ... },
///   ),
///   isScrollControlled: true,
/// );
/// ```
class UserPickerSheet extends StatefulWidget {
  const UserPickerSheet({
    super.key,
    required this.users,
    required this.isLoading,
    required this.onSelected,
    this.title = 'Select User',
  });

  final List<User> users;
  final bool isLoading;
  final void Function(String userId, String displayName) onSelected;
  final String title;

  @override
  State<UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<UserPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  late List<User> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = List<User>.from(widget.users);
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List<User>.from(widget.users)
          : widget.users
              .where((u) =>
                  u.name.toLowerCase().contains(q) ||
                  u.email.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Search users...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('No users found'))
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final u = _filtered[i];
                          final userId = u.email.isNotEmpty ? u.email : u.id;
                          final displayName =
                              u.name.isNotEmpty ? u.name : userId;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.secondaryContainer,
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                    color: colorScheme.onSecondaryContainer),
                              ),
                            ),
                            title: Text(displayName,
                                style:
                                    const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(u.email),
                            onTap: () {
                              // Use Navigator.of(ctx).pop() instead of Get.back().
                              // Get.back() unconditionally calls
                              // Get.closeCurrentSnackbar() before popping; when a
                              // SnackbarController is queued but not yet attached to
                              // the Overlay, its late AnimationController throws
                              // LateInitializationError.
                              Navigator.of(ctx).pop();
                              widget.onSelected(userId, displayName);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
