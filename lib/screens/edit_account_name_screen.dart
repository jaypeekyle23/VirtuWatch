import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';

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
    if (_existingPhotoUrl.isNotEmpty) return NetworkImage(_existingPhotoUrl);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
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
              TextFormField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Enter your name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Your email address can\'t be changed here. Contact an '
                'administrator if you need to update it.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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