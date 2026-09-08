import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';
import '../../services/cloudinary_service.dart';
import '../../theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  final String currentUsername;
  final String currentEmail;
  final List<String> currentStylePreferences;
  final List<String> currentPreferredBrands;
  final double currentBudgetMin;
  final double currentBudgetMax;
  final String currentPhotoUrl;

  const EditProfileScreen({
    super.key,
    required this.currentUsername,
    required this.currentEmail,
    this.currentStylePreferences = const [],
    this.currentPreferredBrands = const [],
    this.currentBudgetMin = 5000,
    this.currentBudgetMax = 50000,
    this.currentPhotoUrl = '',
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _authService = AuthService();
  final _cloudinaryService = CloudinaryService();
  late final TextEditingController _nameController;

  late Set<String> _selectedStyles;
  late Set<String> _selectedBrands;
  late RangeValues _budgetRange;
  late String _existingPhotoUrl;
  File? _selectedImage;
  bool _isUploadingImage = false;

  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _styleOptions = [
    'Classic',
    'Sport',
    'Luxury',
    'Casual',
    'Minimalist',
    'Dress',
    'Vintage',
    'Modern',
  ];

  final List<String> _brandOptions = [
    'Seiko',
    'Orient',
    'Tissot',
    'Citizen',
    'Casio',
    'Tag Heuer',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUsername);
    _selectedStyles = widget.currentStylePreferences.toSet();
    _selectedBrands = widget.currentPreferredBrands.toSet();
    _budgetRange = RangeValues(
      widget.currentBudgetMin.clamp(0, 500000),
      widget.currentBudgetMax.clamp(0, 500000),
    );
    _existingPhotoUrl = widget.currentPhotoUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
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
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Name cannot be empty');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? photoUrl = _existingPhotoUrl.isNotEmpty ? _existingPhotoUrl : null;
      if (_selectedImage != null) {
        setState(() => _isUploadingImage = true);
        try {
          photoUrl = await _cloudinaryService.uploadImage(_selectedImage!);
        } finally {
          if (mounted) setState(() => _isUploadingImage = false);
        }
      }

      await _authService.updateOwnProfile(
        username: _nameController.text.trim(),
        stylePreferences: _selectedStyles.toList(),
        preferredBrands: _selectedBrands.toList(),
        budgetMin: _budgetRange.start,
        budgetMax: _budgetRange.end,
        photoUrl: photoUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
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

  ImageProvider? get _avatarImage {
    if (_selectedImage != null) return FileImage(_selectedImage!);
    if (_existingPhotoUrl.isNotEmpty) return NetworkImage(_existingPhotoUrl);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _isUploadingImage ? null : _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppTheme.gold,
                      backgroundImage: _avatarImage,
                      child: _isUploadingImage
                          ? const CircularProgressIndicator(
                              color: Color(0xFF0E1A2B),
                            )
                          : (_selectedImage == null &&
                                  _existingPhotoUrl.isEmpty)
                              ? Text(
                                  _nameController.text.isNotEmpty
                                      ? _nameController.text.trim()[0]
                                          .toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: Color(0xFF0E1A2B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 24,
                                  ),
                                )
                              : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppTheme.gold,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            size: 14, color: Color(0xFF0E1A2B)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            _fieldLabel('FULL NAME'),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Enter full name'),
            ),
            const SizedBox(height: 16),

            _fieldLabel('EMAIL ADDRESS'),
            TextField(
              enabled: false,
              controller: TextEditingController(text: widget.currentEmail),
              decoration: const InputDecoration(),
            ),
            const SizedBox(height: 4),
            Text(
              'Email cannot be changed here.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 24),

            _fieldLabel('STYLE PREFERENCES'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _styleOptions.map((style) {
                final isSelected = _selectedStyles.contains(style);
                return ChoiceChip(
                  label: Text(style),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedStyles.add(style);
                      } else {
                        _selectedStyles.remove(style);
                      }
                    });
                  },
                  backgroundColor: AppTheme.surface,
                  selectedColor: AppTheme.gold.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppTheme.gold : Colors.transparent,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            _fieldLabel('PREFERRED BRANDS'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _brandOptions.map((brand) {
                final isSelected = _selectedBrands.contains(brand);
                return ChoiceChip(
                  label: Text(brand),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedBrands.add(brand);
                      } else {
                        _selectedBrands.remove(brand);
                      }
                    });
                  },
                  backgroundColor: AppTheme.surface,
                  selectedColor: AppTheme.gold.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppTheme.gold : Colors.transparent,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            _fieldLabel('BUDGET RANGE (PHP)'),
            const SizedBox(height: 8),
            RangeSlider(
              values: _budgetRange,
              min: 0,
              max: 500000,
              divisions: 100,
              activeColor: AppTheme.gold,
              inactiveColor: AppTheme.surface,
              labels: RangeLabels(
                '₱${_budgetRange.start.round()}',
                '₱${_budgetRange.end.round()}',
              ),
              onChanged: (values) {
                setState(() => _budgetRange = values);
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₱${_budgetRange.start.round()}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                Text(
                  '₱${_budgetRange.end.round()}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 24),

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
              onPressed: _isLoading ? null : _handleSave,
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

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}