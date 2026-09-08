import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/cloudinary_service.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';

class MerchantEditWatchScreen extends StatefulWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const MerchantEditWatchScreen({
    super.key,
    required this.watchId,
    required this.data,
  });

  @override
  State<MerchantEditWatchScreen> createState() =>
      _MerchantEditWatchScreenState();
}

class _MerchantEditWatchScreenState extends State<MerchantEditWatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _watchService = WatchService();
  final _cloudinaryService = CloudinaryService();

  late final TextEditingController _nameController;
  late final TextEditingController _brandController;
  late final TextEditingController _priceController;
  late final TextEditingController _caseDiameterController;
  late final TextEditingController _caseThicknessController;
  late final TextEditingController _lugToLugController;
  late final TextEditingController _bandWidthController;
  late final TextEditingController _bandMaterialController;
  late final TextEditingController _caseMaterialController;
  late final TextEditingController _movementTypeController;
  late final TextEditingController _waterResistanceController;

  late String _styleCategory;
  late bool _listedInCatalog;
  bool _isLoading = false;
  String? _errorMessage;

  late String _existingImageUrl;
  File? _selectedImage;
  bool _isUploadingImage = false;

  final List<String> _styleOptions = [
    'Sport',
    'Classic',
    'Luxury',
    'Casual',
    'Minimalist',
    'Dress',
  ];

  String _asString(dynamic value) => value?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    _nameController = TextEditingController(text: _asString(d['name']));
    _brandController = TextEditingController(text: _asString(d['brand']));
    _priceController = TextEditingController(text: _asString(d['price']));
    _caseDiameterController =
        TextEditingController(text: _asString(d['caseDiameterMm']));
    _caseThicknessController =
        TextEditingController(text: _asString(d['caseThicknessMm']));
    _lugToLugController =
        TextEditingController(text: _asString(d['lugToLugMm']));
    _bandWidthController =
        TextEditingController(text: _asString(d['bandWidthMm']));
    _bandMaterialController =
        TextEditingController(text: _asString(d['bandMaterial']));
    _caseMaterialController =
        TextEditingController(text: _asString(d['caseMaterial']));
    _movementTypeController =
        TextEditingController(text: _asString(d['movementType']));
    _waterResistanceController =
        TextEditingController(text: _asString(d['waterResistance']));
    _styleCategory = (d['styleCategory'] as String?) ?? 'Sport';
    _listedInCatalog = (d['listedInCatalog'] as bool?) ?? true;
    _existingImageUrl = (d['imageUrl'] as String?) ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    _caseDiameterController.dispose();
    _caseThicknessController.dispose();
    _lugToLugController.dispose();
    _bandWidthController.dispose();
    _bandMaterialController.dispose();
    _caseMaterialController.dispose();
    _movementTypeController.dispose();
    _waterResistanceController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await _cloudinaryService.pickImage(
      source: ImageSource.gallery,
    );
    if (image != null) {
      setState(() => _selectedImage = image);
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Only touch imageUrl if the merchant picked a new photo — otherwise
      // leave the existing one exactly as-is in Firestore.
      String imageUrl = _existingImageUrl;
      if (_selectedImage != null) {
        setState(() => _isUploadingImage = true);
        try {
          imageUrl = await _cloudinaryService.uploadImage(_selectedImage!);
        } finally {
          if (mounted) setState(() => _isUploadingImage = false);
        }
      }

      await _watchService.updateWatch(widget.watchId, {
        'name': _nameController.text.trim(),
        'brand': _brandController.text.trim(),
        'price': double.parse(_priceController.text.trim()),
        'styleCategory': _styleCategory,
        'caseDiameterMm': double.tryParse(_caseDiameterController.text.trim()),
        'caseThicknessMm':
            double.tryParse(_caseThicknessController.text.trim()),
        'lugToLugMm': double.parse(_lugToLugController.text.trim()),
        'bandWidthMm': double.tryParse(_bandWidthController.text.trim()),
        'bandMaterial': _bandMaterialController.text.trim(),
        'caseMaterial': _caseMaterialController.text.trim(),
        'movementType': _movementTypeController.text.trim(),
        'waterResistance': _waterResistanceController.text.trim(),
        'listedInCatalog': _listedInCatalog,
        'imageUrl': imageUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Watch updated successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Watch'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _handleSave,
            child: Text(
              'Save',
              style: TextStyle(
                color: _isLoading ? AppTheme.textSecondary : AppTheme.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _fieldLabel('WATCH PHOTO'),
              GestureDetector(
                onTap: _isUploadingImage ? null : _pickImage,
                child: Container(
                  height: 160,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.gold.withValues(alpha: 0.4),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _isUploadingImage
                      ? const Center(child: CircularProgressIndicator())
                      : _selectedImage != null
                          ? Image.file(_selectedImage!, fit: BoxFit.cover)
                          : _existingImageUrl.isNotEmpty
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(
                                      _existingImageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Center(
                                        child: Icon(Icons.watch,
                                            size: 40,
                                            color: AppTheme.textSecondary),
                                      ),
                                    ),
                                    Positioned(
                                      right: 8,
                                      bottom: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                              alpha: 0.6),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: const Text(
                                          'Tap to change',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined,
                                        size: 32,
                                        color: AppTheme.textSecondary),
                                    SizedBox(height: 8),
                                    Text('Tap to add a photo',
                                        style: TextStyle(
                                            color: AppTheme.textSecondary)),
                                  ],
                                ),
                ),
              ),
              const SizedBox(height: 16),

              _fieldLabel('WATCH NAME *'),
              TextFormField(
                controller: _nameController,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              _fieldLabel('BRAND'),
              TextFormField(controller: _brandController),
              const SizedBox(height: 16),

              _fieldLabel('PRICE (PHP) *'),
              TextFormField(
                controller: _priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) {
                    return 'Enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              _fieldLabel('STYLE CATEGORY'),
              DropdownButtonFormField<String>(
                initialValue: _styleCategory,
                dropdownColor: AppTheme.surface,
                decoration: const InputDecoration(),
                items: _styleOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (value) {
                  setState(() => _styleCategory = value ?? _styleCategory);
                },
              ),
              const SizedBox(height: 24),

              Text(
                'WATCH SPECIFICATIONS',
                style: TextStyle(
                  color: AppTheme.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('CASE DIAMETER (MM)'),
                        TextFormField(
                          controller: _caseDiameterController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('CASE THICKNESS (MM)'),
                        TextFormField(
                          controller: _caseThicknessController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('LUG-TO-LUG (MM) *'),
                        TextFormField(
                          controller: _lugToLugController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            if (double.tryParse(v.trim()) == null) {
                              return 'Invalid';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('BAND WIDTH (MM)'),
                        TextFormField(
                          controller: _bandWidthController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _fieldLabel('BAND MATERIAL'),
              TextFormField(controller: _bandMaterialController),
              const SizedBox(height: 16),

              _fieldLabel('CASE MATERIAL'),
              TextFormField(controller: _caseMaterialController),
              const SizedBox(height: 16),

              _fieldLabel('MOVEMENT TYPE'),
              TextFormField(controller: _movementTypeController),
              const SizedBox(height: 16),

              _fieldLabel('WATER RESISTANCE'),
              TextFormField(controller: _waterResistanceController),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Listed in Catalog',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Visible to shoppers',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _listedInCatalog,
                      activeThumbColor: AppTheme.gold,
                      onChanged: (v) => setState(() => _listedInCatalog = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),

              ElevatedButton(
                onPressed: _isLoading ? null : _handleSave,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Changes'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}