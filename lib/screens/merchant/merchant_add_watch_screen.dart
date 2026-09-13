import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/watch_colors.dart';
import '../../services/cloudinary_service.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/form_validators.dart';
import '../../widgets/watch_color_picker.dart';
import '../../widgets/watch_color_wheel_picker.dart';

class MerchantAddWatchScreen extends StatefulWidget {
  final bool isAdminMode;

  const MerchantAddWatchScreen({super.key, this.isAdminMode = false});

  @override
  State<MerchantAddWatchScreen> createState() =>
      _MerchantAddWatchScreenState();
}

class _MerchantAddWatchScreenState extends State<MerchantAddWatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _watchService = WatchService();
  final _cloudinaryService = CloudinaryService();

  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _priceController = TextEditingController();
  final _caseDiameterController = TextEditingController();
  final _caseThicknessController = TextEditingController();
  final _lugToLugController = TextEditingController();
  final _bandWidthController = TextEditingController();
  final _bandMaterialController = TextEditingController();
  final _caseMaterialController = TextEditingController();
  final _movementTypeController = TextEditingController();
  final _waterResistanceController = TextEditingController();

  String _styleCategory = 'Sport';
  String _colorHex = watchColorPalette.first.hex;
  bool _useCustomColor = false;
  bool _listedInCatalog = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _selectedMerchantId;

  File? _selectedImage;
  bool _isUploadingImage = false;

  File? _selectedModelFile;
  bool _isUploadingModel = false;
  String? _modelErrorMessage;

  final List<String> _styleOptions = [
    'Sport',
    'Classic',
    'Luxury',
    'Casual',
    'Minimalist',
    'Dress',
  ];

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

  Future<void> _pickModelFile() async {
    try {
      final file = await _cloudinaryService.pickModelFile();
      if (file != null) {
        setState(() {
          _selectedModelFile = file;
          _modelErrorMessage = null;
        });
      }
    } catch (e) {
      setState(() => _modelErrorMessage = e.toString());
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.isAdminMode && _selectedMerchantId == null) {
      setState(() {
        _errorMessage = 'Please select which merchant this watch belongs to.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String imageUrl = '';
      if (_selectedImage != null) {
        setState(() => _isUploadingImage = true);
        try {
          imageUrl = await _cloudinaryService.uploadImage(_selectedImage!);
        } finally {
          if (mounted) setState(() => _isUploadingImage = false);
        }
      }

      String modelUrl = '';
      if (_selectedModelFile != null) {
        setState(() => _isUploadingModel = true);
        try {
          modelUrl = await _cloudinaryService.uploadModel(_selectedModelFile!);
        } finally {
          if (mounted) setState(() => _isUploadingModel = false);
        }
      }

      await _watchService.addWatch(
        {
          'name': _nameController.text.trim(),
          'brand': _brandController.text.trim(),
          'price': double.parse(_priceController.text.trim()),
          'styleCategory': _styleCategory,
          'colorHex': _colorHex,
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
          'has3DModel': modelUrl.isNotEmpty,
          'modelUrl': modelUrl,
          'imageUrl': imageUrl,
        },
        merchantIdOverride: widget.isAdminMode ? _selectedMerchantId : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Watch added successfully!')),
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
        title: const Text('Add Watch'),
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
              if (widget.isAdminMode) ...[
                _fieldLabel('MERCHANT *'),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'merchant')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final merchants = snapshot.data?.docs ?? [];
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (merchants.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'No merchant accounts exist yet. Create one first.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      );
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: _selectedMerchantId,
                      dropdownColor: AppTheme.surface,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(hintText: 'Select a merchant'),
                      items: merchants.map((doc) {
                        final data = doc.data();
                        final name = data['username'] as String? ?? 'Merchant';
                        final email = data['email'] as String? ?? '';
                        return DropdownMenuItem(
                          value: doc.id,
                          child: Text(
                            '$name ($email)',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => _selectedMerchantId = value);
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],

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
                  child: _isUploadingImage
                      ? const Center(child: CircularProgressIndicator())
                      : _selectedImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_selectedImage!, fit: BoxFit.cover),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined,
                                    size: 32, color: AppTheme.textSecondary),
                                SizedBox(height: 8),
                                Text('Tap to add a photo',
                                    style: TextStyle(color: AppTheme.textSecondary)),
                              ],
                            ),
                ),
              ),
              const SizedBox(height: 16),

              _fieldLabel('WATCH NAME *'),
              TextFormField(
                controller: _nameController,
                decoration:
                    const InputDecoration(hintText: 'e.g. Seiko Prospex SPB143J1'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),

              _fieldLabel('BRAND'),
              TextFormField(
                controller: _brandController,
                decoration: const InputDecoration(hintText: 'e.g. Seiko'),
              ),
              const SizedBox(height: 16),

              _fieldLabel('PRICE (PHP) *'),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: 'e.g. 15000'),
                validator: requiredPositiveNumber,
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
              const SizedBox(height: 16),

              _fieldLabel('PRIMARY COLOR'),
              WatchColorPicker(
                selectedHex: _colorHex,
                onChanged: (hex) => setState(() {
                  _colorHex = hex;
                  _useCustomColor = false;
                }),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _useCustomColor = !_useCustomColor),
                icon: Icon(
                  _useCustomColor
                      ? Icons.expand_less
                      : Icons.color_lens_outlined,
                  size: 16,
                  color: AppTheme.gold,
                ),
                label: Text(
                  _useCustomColor
                      ? 'Hide custom color'
                      : "Don't see a match? Use a custom color",
                  style: TextStyle(color: AppTheme.gold, fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
              ),
              if (_useCustomColor) ...[
                const SizedBox(height: 8),
                WatchColorWheelPicker(
                  initialHex: _colorHex,
                  onChanged: (hex) => setState(() => _colorHex = hex),
                ),
              ],
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
                          decoration: const InputDecoration(hintText: '42.0'),
                          validator: optionalPositiveNumber,
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
                          decoration: const InputDecoration(hintText: '13.5'),
                          validator: optionalPositiveNumber,
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
                          decoration: const InputDecoration(hintText: '46.5'),
                          validator: requiredPositiveNumber,
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
                          decoration: const InputDecoration(hintText: '22'),
                          validator: optionalPositiveNumber,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.gold, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lug-to-lug determines AI wrist fit matching',
                        style: TextStyle(color: AppTheme.gold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _fieldLabel('BAND MATERIAL'),
              TextFormField(
                controller: _bandMaterialController,
                decoration:
                    const InputDecoration(hintText: 'e.g. Stainless Steel, Leather'),
              ),
              const SizedBox(height: 16),

              _fieldLabel('CASE MATERIAL'),
              TextFormField(
                controller: _caseMaterialController,
                decoration: const InputDecoration(hintText: 'e.g. Stainless Steel'),
              ),
              const SizedBox(height: 16),

              _fieldLabel('MOVEMENT TYPE'),
              TextFormField(
                controller: _movementTypeController,
                decoration: const InputDecoration(hintText: 'e.g. Automatic, Quartz'),
              ),
              const SizedBox(height: 16),

              _fieldLabel('WATER RESISTANCE'),
              TextFormField(
                controller: _waterResistanceController,
                decoration: const InputDecoration(hintText: 'e.g. 100m / 10 ATM'),
              ),
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
              const SizedBox(height: 16),

              GestureDetector(
                onTap: _isUploadingModel ? null : _pickModelFile,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selectedModelFile != null
                          ? AppTheme.gold.withValues(alpha: 0.4)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      if (_isUploadingModel)
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _selectedModelFile != null
                              ? Icons.check_circle
                              : Icons.threed_rotation,
                          color: _selectedModelFile != null
                              ? AppTheme.gold
                              : AppTheme.textSecondary,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isUploadingModel
                                  ? 'Uploading model...'
                                  : _selectedModelFile != null
                                      ? _selectedModelFile!.path
                                          .split(Platform.pathSeparator)
                                          .last
                                      : '3D Model (optional)',
                              style: TextStyle(
                                color: _selectedModelFile != null
                                    ? AppTheme.textPrimary
                                    : AppTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: _selectedModelFile != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_selectedModelFile == null &&
                                !_isUploadingModel)
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  'Tap to attach a .glb or .gltf file for AR try-on',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_selectedModelFile != null && !_isUploadingModel)
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppTheme.textSecondary, size: 18),
                          onPressed: () =>
                              setState(() => _selectedModelFile = null),
                        ),
                    ],
                  ),
                ),
              ),
              if (_modelErrorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _modelErrorMessage!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12),
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
                    : const Text('Save Watch'),
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