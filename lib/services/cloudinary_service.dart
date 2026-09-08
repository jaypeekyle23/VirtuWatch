import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Handles picking an image from the device and uploading it to Cloudinary,
/// returning the resulting hosted URL to store in Firestore (e.g. a watch's
/// imageUrl or a user's profile photo URL).
class CloudinaryService {
  // TODO: replace with your actual Cloudinary values.
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
}