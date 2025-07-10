import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

class MediaService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _imagePicker = ImagePicker();

  Future<String?> uploadImage({
    required String userId,
    required ImageSource source,
    bool isMessage = false,
  }) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 70,
      );

      if (image == null) return null;

      final String fileName = '${const Uuid().v4()}${path.extension(image.path)}';
      final String folderPath = isMessage ? 'messages' : 'profiles';
      final Reference ref = _storage.ref().child('$folderPath/$userId/$fileName');

      final UploadTask uploadTask = ref.putFile(File(image.path));
      final TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  Future<String?> uploadVideo({
    required String userId,
    required ImageSource source,
  }) async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 5),
      );

      if (video == null) return null;

      final String fileName = '${const Uuid().v4()}${path.extension(video.path)}';
      final Reference ref = _storage.ref().child('messages/$userId/videos/$fileName');

      final UploadTask uploadTask = ref.putFile(File(video.path));
      final TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('Error uploading video: $e');
      return null;
    }
  }

  Future<Map<String, String>?> uploadFile({
    required String userId,
  }) async {
    try {
      // Use image_picker to pick a file (it will be treated as a media file)
      final XFile? pickedFile = await _imagePicker.pickMedia();

      if (pickedFile == null) return null;

      final File file = File(pickedFile.path);
      final String fileName = path.basename(pickedFile.path);
      final Reference ref = _storage.ref().child('messages/$userId/files/$fileName');

      final UploadTask uploadTask = ref.putFile(file);
      final TaskSnapshot snapshot = await uploadTask;
      final String url = await snapshot.ref.getDownloadURL();

      return {
        'name': fileName,
        'url': url,
        'size': (await file.length()).toString(),
        'type': path.extension(fileName),
      };
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  Future<String?> uploadAudio({
    required String userId,
    required String filePath,
  }) async {
    try {
      final String fileName = '${const Uuid().v4()}.aac';
      final Reference ref = _storage.ref().child('messages/$userId/audio/$fileName');

      final UploadTask uploadTask = ref.putFile(File(filePath));
      final TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('Error uploading audio: $e');
      return null;
    }
  }

  Future<void> deleteFile(String url) async {
    try {
      final Reference ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (e) {
      print('Error deleting file: $e');
    }
  }

  Future<Map<String, dynamic>?> pickAndEncodeImage({
    required bool isMessage,
  }) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (image == null) return null;
      final bytes = await File(image.path).readAsBytes();
      if (bytes.length > 900 * 1024) {
        return {'error': 'Image too large (max 900KB)'};
      }
      final base64 = base64Encode(bytes);
      return {
        'base64': base64,
        'name': path.basename(image.path),
        'type': path.extension(image.path),
        'size': bytes.length,
      };
    } catch (e) {
      print('Error picking/encoding image: $e');
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> pickAndEncodeVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (video == null) return null;
      final bytes = await File(video.path).readAsBytes();
      if (bytes.length > 900 * 1024) {
        return {'error': 'Video too large (max 900KB)'};
      }
      final base64 = base64Encode(bytes);
      return {
        'base64': base64,
        'name': path.basename(video.path),
        'type': path.extension(video.path),
        'size': bytes.length,
      };
    } catch (e) {
      print('Error picking/encoding video: $e');
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>?> pickAndEncodeFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      if (file.size > 900 * 1024) {
        return {'error': 'File too large (max 900KB)'};
      }
      final base64 = base64Encode(file.bytes ?? await File(file.path!).readAsBytes());
      return {
        'base64': base64,
        'name': file.name,
        'type': file.extension ?? '',
        'size': file.size,
      };
    } catch (e) {
      print('Error picking/encoding file: $e');
      return {'error': e.toString()};
    }
  }
} 