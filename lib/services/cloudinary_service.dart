import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../utils/glb_header.dart';

/// Handles picking an image from the device and uploading it to Cloudinary,
/// returning the resulting hosted URL to store in Firestore (e.g. a watch's
/// imageUrl or a user's profile photo URL).
class CloudinaryService {
  // Live Cloudinary account for this project (unsigned upload preset,
  // scoped to image/model uploads only).
  static const String _cloudName = 'o9fetve3';
  static const String _uploadPreset = 'virtuwatch_uploads';

  final ImagePicker _picker = ImagePicker();

  /// Opens the device's image picker (gallery). Returns null if the user
  /// cancels without selecting anything.
  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    final pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 85, // light compression, keeps uploads fast
    );
    if (pickedFile == null) return null;
    return File(pickedFile.path);
  }

  /// Opens the device's gallery allowing multiple images to be selected
  /// at once. Returns an empty list if the user cancels without picking
  /// anything.
  Future<List<File>> pickMultipleImages() async {
    final pickedFiles = await _picker.pickMultiImage(imageQuality: 85);
    return pickedFiles.map((f) => File(f.path)).toList();
  }

  /// Uploads an image file to Cloudinary using the unsigned preset and
  /// returns the hosted image URL. Throws a readable error string on
  /// failure so calling screens can show it directly.
  Future<String> uploadImage(File imageFile) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    try {
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw 'Image upload failed (${response.statusCode}). Please try again.';
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final url = data['secure_url'] as String?;
      if (url == null) {
        throw 'Upload succeeded but no URL was returned.';
      }
      return url;
    } catch (e) {
      if (e is String) rethrow;
      throw 'Could not upload image. Check your connection and try again.';
    }
  }

  /// Opens the device's file picker filtered to .glb 3D models. Returns null
  /// if the user cancels. Throws a readable error string if the file isn't a
  /// real .glb.
  ///
  /// Only .glb is accepted: a .gltf comes as several separate files (JSON plus
  /// .bin and textures), which a single-file upload can't carry. The OS
  /// picker's extension filter is only a hint, so the file name and then its
  /// first bytes (the "glTF" magic) are checked here. That also catches a file
  /// that was simply renamed to .glb.
  Future<File?> pickModelFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['glb'],
    );
    if (file == null || file.path == null) return null;

    final extension = file.name.split('.').last.toLowerCase();
    if (extension != 'glb') {
      throw 'Please select a .glb 3D model file (you picked a .$extension file). '
          '.gltf files are not supported because they come as several separate files.';
    }

    final model = File(file.path!);
    final raf = await model.open();
    final List<int> header;
    try {
      header = await raf.read(4);
    } finally {
      await raf.close();
    }
    if (!isGlbHeader(header)) {
      throw 'This file is not a valid .glb model. Re-export it as a binary glTF (.glb).';
    }

    return model;
  }

  /// Uploads a 3D model file (.glb) to Cloudinary and returns the
  /// hosted URL. Models are uploaded as a "raw" resource type since
  /// Cloudinary's image/video pipelines don't apply here.
  ///
  /// Note: the free Cloudinary plan caps raw file uploads at 10MB — keep
  /// exported .glb models reasonably compressed (e.g. via Blender's glTF
  /// export with Draco compression) to stay under that comfortably.
  Future<String> uploadModel(File modelFile) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/raw/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', modelFile.path));

    try {
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        // Cloudinary's actual reason lives in the response body
        // (data['error']['message']) — surfacing it instead of just the
        // status code is the difference between "something broke" and
        // "here's exactly what to fix in the preset/console".
        String reason = 'HTTP ${response.statusCode}';
        try {
          final errorData = jsonDecode(responseBody) as Map<String, dynamic>;
          final message = (errorData['error'] as Map?)?['message'] as String?;
          if (message != null && message.isNotEmpty) reason = message;
        } catch (_) {
          // Body wasn't JSON (or didn't match the expected shape) —
          // fall back to the raw status code above.
        }
        // ignore: avoid_print
        debugPrint('Cloudinary model upload failed: $reason\nBody: $responseBody');
        throw 'Model upload failed: $reason';
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final url = data['secure_url'] as String?;
      if (url == null) {
        throw 'Upload succeeded but no URL was returned.';
      }
      return url;
    } catch (e) {
      if (e is String) rethrow;
      throw 'Could not upload 3D model. Check your connection and try again.';
    }
  }
}