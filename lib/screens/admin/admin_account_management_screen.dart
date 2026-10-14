import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/skeleton_box.dart';
import 'admin_create_account_screen.dart';

class AdminAccountManagementScreen extends StatefulWidget {
  const AdminAccountManagementScreen({super.key});

  @override
  State<AdminAccountManagementScreen> createState() =>
      _AdminAccountManagementScreenState();
}

class _AdminAccountManagementScreenState
    extends State<AdminAccountManagementScreen> {
  static const _filters = ['All', 'Active', 'Disabled', 'Admin', 'Merchant'];

  final _userService = UserService();
  final _search = TextEditingController();
  // Created once so rebuilds don't re-subscribe and flash the skeletons.
  late final _users = _userService.allUsers();

  String _query = '';
  String _filter = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Map<String, dynamic> d) {
    final inFilter = switch (_filter) {
      'Active' => d['accountStatus'] == 'active',
      'Disabled' => d['accountStatus'] == 'suspended',
      'Admin' || 'Merchant' => d['role'] == _filter.toLowerCase(),
      _ => true,
    };
    return inFilter &&
        (_query.isEmpty ||
            '${d['username'] ?? ''} ${d['email'] ?? ''}'
                .toLowerCase()
                .contains(_query));
  }

  void _toast(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<bool> _confirm(String title, String body, String action,
          {bool danger = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(title, style: AppTheme.serif(size: 22)),
          content: Text(body,
              style:
                  TextStyle(color: AppTheme.textSecondary, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action,
                  style: danger ? const TextStyle(color: Colors.redAccent) : null),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _onAction(String action, String uid, Map<String, dynamic> d) async {
    final name = d['username'];
    final label = '$name (${d['email']})';
    switch (action) {
      case 'disable':
        await _userService.suspendAccount(uid, accountLabel: label);
        if (mounted) _toast('Account disabled.');
      case 'enable':
        await _userService.reactivateAccount(uid, accountLabel: label);
        if (mounted) _toast('Account re-enabled.');
      case 'change_role':
        await _changeRole(uid, d, label);
      case 'delete':
        if (await _confirm(
            'Delete account?',
            'This will permanently remove "$name"\'s profile. This cannot be undone.',
            'Delete',
            danger: true)) {
          await _userService.deleteAccountProfile(uid, accountLabel: label);
          if (mounted) _toast('Account profile deleted.');
        }
    }
  }

  Future<void> _changeRole(
      String uid, Map<String, dynamic> d, String label) async {
    final current = d['role'] as String? ?? 'customer';
    var selected = current;

    final next = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialog) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text('Change role', style: AppTheme.serif(size: 22)),
          content: RadioGroup<String>(
            groupValue: selected,
            onChanged: (v) => setDialog(() => selected = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final r in ['customer', 'merchant', 'admin'])
                  RadioListTile<String>(
                    value: r,
                    activeColor: AppTheme.gold,
                    title: Text(r[0].toUpperCase() + r.substring(1),
                        style: TextStyle(color: AppTheme.textPrimary)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  selected == current ? null : () => Navigator.pop(c, selected),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (next == null || !mounted) return;

    final toAdmin = next == 'admin';
    final ok = await _confirm(
      toAdmin ? 'Grant admin access?' : 'Confirm role change',
      toAdmin
          ? '"${d['username']}" will gain full administrative access, including account and catalog management for the entire platform. Are you sure?'
          : 'Change "${d['username']}"\'s role from ${current.toUpperCase()} to ${next.toUpperCase()}?',
      toAdmin ? 'Grant access' : 'Confirm',
      danger: toAdmin,
    );
    if (!ok) return;

    try {
      await _userService.updateUserRole(uid, next,
          accountLabel: label, previousRole: current);
      if (mounted) _toast('Role updated to ${next.toUpperCase()}.');
    } catch (e) {
      if (mounted) _toast(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Accounts', style: AppTheme.serif(size: 28)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add account',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdminCreateAccountScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              controller: _search,
              style: const TextStyle(fontSize: 15),
              decoration: luxeFieldDecoration(
                hint: 'Search by name or email',
                prefixIcon: Icon(Icons.search,
                    size: 20, color: AppTheme.textSecondary),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: AppTheme.textSecondary,
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => luxePill(_filters[i],
                  selected: _filter == _filters[i],
                  onTap: () => setState(() => _filter = _filters[i])),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _users,
              builder: (context, snap) {
                if (snap.hasError) return _message('Could not load accounts.');
                if (!snap.hasData) {
                  return ListView(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [for (var i = 0; i < 7; i++) const _RowSkeleton()],
                  );
                }
                final docs =
                    snap.data!.docs.where((d) => _matches(d.data())).toList();
                if (docs.isEmpty) return _message('No accounts found.');
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [for (final d in docs) _row(d.id, d.data())],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Text(text,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      );

  Widget _row(String uid, Map<String, dynamic> d) {
    final username = d['username'] as String? ?? 'Unknown';
    final photoUrl = d['photoUrl'] as String? ?? '';
    final isActive = (d['accountStatus'] ?? 'active') == 'active';
    final isSelf = uid == FirebaseAuth.instance.currentUser?.uid;
    final initials = username
        .trim()
        .split(' ')
        .where((e) => e.isNotEmpty)
        .map((e) => e[0])
        .take(2)
        .join()
        .toUpperCase();
    final note = [if (!isActive) 'DISABLED', if (isSelf) 'YOU'].join('  ·  ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.hairline)),
      ),
      child: Opacity(
        opacity: isActive ? 1 : 0.55,
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppTheme.surface,
              backgroundImage:
                  photoUrl.isNotEmpty ? NetworkPhoto.provider(photoUrl) : null,
              child: photoUrl.isEmpty
                  ? Text(initials.isEmpty ? '?' : initials,
                      style: AppTheme.serif(size: 16))
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  Text(d['email'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text((d['role'] as String? ?? 'customer').toUpperCase(),
                    style: kLabelStyle.copyWith(
                        color: AppTheme.textPrimary, fontSize: 10)),
                if (note.isNotEmpty)
                  Text(note, style: kLabelStyle.copyWith(fontSize: 9)),
              ],
            ),
            PopupMenuButton<String>(
              color: AppTheme.surface,
              padding: const EdgeInsets.only(left: 8),
              icon: Icon(Icons.more_vert,
                  size: 20, color: AppTheme.textSecondary),
              onSelected: (v) => _onAction(v, uid, d),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: isActive ? 'disable' : 'enable',
                  child: Text(isActive ? 'Disable account' : 'Enable account',
                      style: TextStyle(color: AppTheme.textPrimary)),
                ),
                if (!isSelf)
                  PopupMenuItem(
                    value: 'change_role',
                    child: Text('Change role',
                        style: TextStyle(color: AppTheme.textPrimary)),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete account',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shaped like an account row.
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SkeletonBox(
              width: 40,
              height: 40,
              borderRadius: BorderRadius.all(Radius.circular(20)),
            ),
            SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 13),
                SizedBox(height: 6),
                SkeletonBox(width: 160, height: 11),
              ],
            ),
          ],
        ),
      );
}