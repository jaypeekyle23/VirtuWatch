import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import 'admin_create_account_screen.dart';

class AdminAccountManagementScreen extends StatefulWidget {
  const AdminAccountManagementScreen({super.key});

  @override
  State<AdminAccountManagementScreen> createState() =>
      _AdminAccountManagementScreenState();
}

class _AdminAccountManagementScreenState
    extends State<AdminAccountManagementScreen> {
  final _userService = UserService();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedFilter = 'All';

  final List<String> _filters = [
    'All',
    'Active',
    'Disabled',
    'Admin',
    'Merchant',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add Account',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminCreateAccountScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: AppTheme.textSecondary,
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedFilter = filter),
                  backgroundColor: AppTheme.surface,
                  selectedColor: AppTheme.gold.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppTheme.gold : Colors.transparent,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _userService.allUsers(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data?.docs ?? [];

                if (_selectedFilter == 'Active' || _selectedFilter == 'Disabled') {
                  final wantStatus =
                      _selectedFilter == 'Active' ? 'active' : 'suspended';
                  docs = docs
                      .where((d) => d.data()['accountStatus'] == wantStatus)
                      .toList();
                } else if (_selectedFilter == 'Admin' ||
                    _selectedFilter == 'Merchant') {
                  docs = docs
                      .where((d) =>
                          d.data()['role'] == _selectedFilter.toLowerCase())
                      .toList();
                }

                if (_searchQuery.isNotEmpty) {
                  docs = docs.where((d) {
                    final data = d.data();
                    final username =
                        (data['username'] as String? ?? '').toLowerCase();
                    final email = (data['email'] as String? ?? '').toLowerCase();
                    return username.contains(_searchQuery) ||
                        email.contains(_searchQuery);
                  }).toList();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No accounts found.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    return _AccountTile(
                      uid: doc.id,
                      data: doc.data(),
                      userService: _userService,
                    );
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

class _AccountTile extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final UserService userService;

  const _AccountTile({
    required this.uid,
    required this.data,
    required this.userService,
  });

  @override
  Widget build(BuildContext context) {
    final username = data['username'] as String? ?? 'Unknown';
    final email = data['email'] as String? ?? '';
    final role = (data['role'] as String? ?? 'customer');
    final status = (data['accountStatus'] as String? ?? 'active');
    final isActive = status == 'active';
    final isSelf = uid == FirebaseAuth.instance.currentUser?.uid;
    final initials = username.isNotEmpty
        ? username.trim().split(' ').map((e) => e[0]).take(2).join()
        : '?';

    final roleColor = switch (role) {
      'admin' => Colors.redAccent,
      'merchant' => Colors.greenAccent,
      _ => AppTheme.gold,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: roleColor.withValues(alpha: 0.2),
            child: Text(
              initials.toUpperCase(),
              style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  email,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    _badge(role.toUpperCase(), roleColor),
                    _badge(
                      isActive ? 'ACTIVE' : 'DISABLED',
                      isActive ? Colors.greenAccent : Colors.redAccent,
                    ),
                    if (isSelf) _badge('YOU', AppTheme.textSecondary),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            color: AppTheme.surface,
            icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
            onSelected: (value) => _handleAction(context, value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: isActive ? 'disable' : 'enable',
                child: Text(
                  isActive ? 'Disable Account' : 'Enable Account',
                  style: const TextStyle(color: AppTheme.textPrimary),
                ),
              ),
              if (!isSelf)
                const PopupMenuItem(
                  value: 'change_role',
                  child: Text('Change Role',
                      style: TextStyle(color: AppTheme.textPrimary)),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete Account',
                    style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    if (action == 'disable') {
      await userService.suspendAccount(uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account disabled.')),
        );
      }
    } else if (action == 'enable') {
      await userService.reactivateAccount(uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account re-enabled.')),
        );
      }
    } else if (action == 'change_role') {
      await _showChangeRoleDialog(context);
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Delete Account?',
              style: TextStyle(color: AppTheme.textPrimary)),
          content: Text(
            'This will permanently remove "${data['username']}"\'s profile. This cannot be undone.',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await userService.deleteAccountProfile(uid);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account profile deleted.')),
          );
        }
      }
    }
  }

  Future<void> _showChangeRoleDialog(BuildContext context) async {
    final currentRole = data['role'] as String? ?? 'customer';
    String selectedRole = currentRole;

    final confirmedRole = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: Text(
              'Change Role for ${data['username']}',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            content: RadioGroup<String>(
              groupValue: selectedRole,
              onChanged: (value) {
                setDialogState(() => selectedRole = value!);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: ['customer', 'merchant', 'admin'].map((r) {
                  return RadioListTile<String>(
                    value: r,
                    activeColor: AppTheme.gold,
                    title: Text(
                      r[0].toUpperCase() + r.substring(1),
                      style: const TextStyle(color: AppTheme.textPrimary),
                    ),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: selectedRole == currentRole
                    ? null
                    : () => Navigator.of(context).pop(selectedRole),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmedRole == null || !context.mounted) return;

    final isPromotingToAdmin = confirmedRole == 'admin';
    final finalConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          isPromotingToAdmin ? 'Grant Admin Access?' : 'Confirm Role Change',
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          isPromotingToAdmin
              ? '"${data['username']}" will gain full administrative access, including account and catalog management for the entire platform. Are you sure?'
              : 'Change "${data['username']}"\'s role from ${currentRole.toUpperCase()} to ${confirmedRole.toUpperCase()}?',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              isPromotingToAdmin ? 'Grant Admin Access' : 'Confirm',
              style: TextStyle(
                color: isPromotingToAdmin
                    ? Colors.redAccent
                    : AppTheme.gold,
              ),
            ),
          ),
        ],
      ),
    );

    if (finalConfirm == true) {
      try {
        await userService.updateUserRole(uid, confirmedRole);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Role updated to ${confirmedRole.toUpperCase()}.'),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.toString())),
          );
        }
      }
    }
  }
}