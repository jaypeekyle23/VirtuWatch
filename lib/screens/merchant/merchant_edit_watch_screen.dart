import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/watch_form.dart';

class MerchantEditWatchScreen extends StatefulWidget {
  final String watchId;
  final Map<String, dynamic> data;

  /// True when an admin is editing: shows the AR fit section.
  final bool showArFit;

  const MerchantEditWatchScreen({
    super.key,
    required this.watchId,
    required this.data,
    this.showArFit = false,
  });

  @override
  State<MerchantEditWatchScreen> createState() =>
      _MerchantEditWatchScreenState();
}

class _MerchantEditWatchScreenState extends State<MerchantEditWatchScreen> {
  final _form = GlobalKey<WatchFormState>();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _save() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final fields = await _form.currentState!.collect();
      if (fields == null) return;

      await WatchService().updateWatch(widget.watchId, fields);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Watch updated successfully!')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Watch', style: AppTheme.serif(size: 28)),
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
              initialData: widget.data,
              showArFit: widget.showArFit,
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
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}