import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/luxe.dart';
import '../../widgets/watch_form.dart';

class MerchantAddWatchScreen extends StatefulWidget {
  /// When true, the watch is assigned to a merchant picked from a list
  /// instead of the signed-in account.
  final bool isAdminMode;

  const MerchantAddWatchScreen({super.key, this.isAdminMode = false});

  @override
  State<MerchantAddWatchScreen> createState() => _MerchantAddWatchScreenState();
}

class _MerchantAddWatchScreenState extends State<MerchantAddWatchScreen> {
  final _form = GlobalKey<WatchFormState>();
  late final _merchants = FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: 'merchant')
      .snapshots();

  String? _merchantId;
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _save() async {
    if (widget.isAdminMode && _merchantId == null) {
      setState(() => _errorMessage =
          'Please select which merchant this watch belongs to.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fields = await _form.currentState!.collect();
      if (fields == null) return;

      await WatchService().addWatch(
        fields,
        merchantIdOverride: widget.isAdminMode ? _merchantId : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Watch added successfully!')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _merchantPicker() {
    return luxeSection(
      'MERCHANT',
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _merchants,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 40,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final merchants = snapshot.data?.docs ?? [];
          if (merchants.isEmpty) {
            return Text('No merchant accounts exist yet. Create one first.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13));
          }
          return DropdownButtonFormField<String>(
            initialValue: _merchantId,
            isExpanded: true,
            dropdownColor: AppTheme.surface,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 15),
            decoration: luxeFieldDecoration(hint: 'Select a merchant'),
            items: [
              for (final doc in merchants)
                DropdownMenuItem(
                  value: doc.id,
                  child: Text(
                    '${doc.data()['username'] ?? 'Merchant'} '
                    '(${doc.data()['email'] ?? ''})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _merchantId = value),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Watch', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WatchForm(
              key: _form,
              header: widget.isAdminMode ? _merchantPicker() : null,
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            ElevatedButton(
              onPressed: _isLoading ? null : _save,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save Watch'),
            ),
          ],
        ),
      ),
    );
  }
}