import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';
import '../widgets/luxe.dart';
import '../widgets/network_photo.dart';

class EditAccountNameScreen extends StatefulWidget {
  final String currentUsername;
  final String currentPhotoUrl;

  const EditAccountNameScreen({
    super.key,
    required this.currentUsername,
    this.currentPhotoUrl = '',
  });

  @override
  State<EditAccountNameScreen> createState() => _EditAccountNameScreenState();
}

class _EditAccountNameScreenState extends State<EditAccountNameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _cloudinaryService = CloudinaryService();
  late final TextEditingController _nameController;

  late String _existingPhotoUrl;
  File? _selectedImage;
  bool _isUploadingImage = false;

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUsername);
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
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_selectedImage != null) {
        setState(() => _isUploadingImage = true);
        String photoUrl = _existingPhotoUrl;
        try {
          photoUrl = await _cloudinaryService.uploadImage(_selectedImage!);
        } finally {
          if (mounted) setState(() => _isUploadingImage = false);
        }
        await _authService.updatePhotoUrl(photoUrl);
      }

      await _authService.updateUsername(_nameController.text.trim());
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
        setState(() => _isLoading = false);
      }
    }
  }

  ImageProvider? get _avatarImage {
    if (_selectedImage != null) return FileImage(_selectedImage!);
    if (_existingPhotoUrl.isNotEmpty) {
      return NetworkPhoto.provider(_existingPhotoUrl);
    }
    return null;
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
        child: Form(
          key: _formKey,
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
                        child: Text('CHANGE PHOTO',
                            style: kLabelStyle.copyWith(
                                color: AppTheme.textPrimary)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              luxeSection(
                'FULL NAME',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 15),
                      decoration:
                          luxeFieldDecoration(hint: 'Enter your name'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Please enter your name'
                              : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Your email address can't be changed here. Contact an "
                      'administrator if you need to update it.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11),
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
      ),
    );
  }
}