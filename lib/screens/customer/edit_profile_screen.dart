import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/auth_service.dart';
import '../../services/cloudinary_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';

class EditProfileScreen extends StatefulWidget {
  final String currentUsername;
  final String currentEmail;
  final List<String> currentStylePreferences;
  final List<String> currentPreferredBrands;
  final double currentBudgetMin;
  final double currentBudgetMax;
  final String currentPhotoUrl;
  final String? currentGender;

  const EditProfileScreen({
    super.key,
    required this.currentUsername,
    required this.currentEmail,
    this.currentStylePreferences = const [],
    this.currentPreferredBrands = const [],
    this.currentBudgetMin = 0,
    this.currentBudgetMax = 50000,
    this.currentPhotoUrl = '',
    this.currentGender,
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
  // 'Male', 'Female', or null for prefer not to say.
  String? _gender;
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
    _gender = widget.currentGender;
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
        gender: _gender,
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
    if (_existingPhotoUrl.isNotEmpty) return NetworkPhoto.provider(_existingPhotoUrl);
    return null;
  }

  /// Pill toggles for a multi-select option list.
  Widget _choices(List<String> options, Set<String> selected) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final option in options)
          luxePill(
            option,
            selected: selected.contains(option),
            onTap: () => setState(() {
              if (!selected.remove(option)) selected.add(option);
            }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();
    final avatar = _avatarImage;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppTheme.surface,
                    backgroundImage: avatar,
                    child: _isUploadingImage
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : (avatar == null
                            ? Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                                style: AppTheme.serif(size: 28))
                            : null),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _isUploadingImage ? null : _pickImage,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'CHANGE PHOTO',
                        style:
                            kLabelStyle.copyWith(color: AppTheme.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            luxeSection(
              'NAME',
              TextField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 15),
                decoration: luxeFieldDecoration(hint: 'Enter full name'),
              ),
            ),
            luxeSection(
              'EMAIL',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.currentEmail,
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('Email cannot be changed here.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            luxeSection(
              'GENDER',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in const ['Male', 'Female', null])
                        luxePill(
                          option ?? 'Prefer not to say',
                          selected: _gender == option,
                          onTap: () => setState(() => _gender = option),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Used to leave out watches made for another gender. '
                    'Unisex watches are always included.',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            luxeSection('STYLE', _choices(_styleOptions, _selectedStyles)),
            luxeSection(
                'PREFERRED BRANDS', _choices(_brandOptions, _selectedBrands)),
            luxeSection(
              'BUDGET',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatPeso(_budgetRange.start)}  to  '
                    '${formatPeso(_budgetRange.end)}',
                    style: AppTheme.serif(size: 22),
                  ),
                  RangeSlider(
                    values: _budgetRange,
                    min: 0,
                    max: 500000,
                    divisions: 100,
                    activeColor: AppTheme.textPrimary,
                    inactiveColor: AppTheme.outline,
                    labels: RangeLabels(
                      formatPeso(_budgetRange.start),
                      formatPeso(_budgetRange.end),
                    ),
                    onChanged: (values) =>
                        setState(() => _budgetRange = values),
                  ),
                ],
              ),
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
}