import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:video_compress/video_compress.dart';
import 'package:cloudinary_public/cloudinary_public.dart';

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

  Future<Map<String, String>?> uploadAudio({
    required String userId,
    required String filePath,
  }) async {
    try {
      // --- BASE64 ENCODE FOR FIRESTORE (active) ---
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final base64Audio = base64Encode(bytes);
      return {
        'base64': base64Audio,
        'publicId': '', // Not used
      };

      // --- FIREBASE STORAGE UPLOAD (keep for future) ---
      /*
      final String fileName = '${const Uuid().v4()}.m4a';
      final Reference ref = _storage.ref().child('messages/$userId/audio/$fileName');
      final UploadTask uploadTask = ref.putFile(File(filePath));
      final TaskSnapshot snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      return {
        'url': url,
        'publicId': '',
      };
      */

      // --- CLOUDINARY UPLOAD (keep for future) ---
      /*
      final cloudinary = CloudinaryPublic(
        'dyyjb1ekx',
        'unsigned',
        cache: false,
      );
      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          filePath,
          resourceType: CloudinaryResourceType.Video,
          folder: 'flyer_chat/audio/$userId',
        ),
      );
      return {
        'url': response.secureUrl,
        'publicId': response.publicId,
      };
      */
    } catch (e) {
      print('Error uploading audio: $e');
      return null;
    }
  }

  Future<bool> deleteCloudinaryAudio(String publicId) async {
    try {
      final cloudinary = CloudinaryPublic(
        'dyyjb1ekx',
        'unsigned',
        cache: false,
      );
     // await cloudinary.deleteFile(publicId: publicId, resourceType: CloudinaryResourceType.Video); // todo: delete audio from cloudinary requires backend
      return true;
    } catch (e) {
      print('Error deleting audio from Cloudinary: $e');
      return false;
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
        imageQuality: 100, // Lower quality for more aggressive compression
      );
      if (image == null) return null;
      // Try to resize and compress further if needed
      var bytes = await File(image.path).readAsBytes();
      if (bytes.length > 900 * 1024) {
        // Try resizing
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final resized = img.copyResize(decoded, width: 800); // Resize to max 800px width
          bytes = img.encodeJpg(resized, quality: 30); // Lower quality
        }
      }
      if (bytes.length > 900 * 1024) {
        return {'error': 'Image could not be compressed below 900KB and cannot be uploaded.'};
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
      File file = File(video.path);
      // Try to compress video
      MediaInfo? compressed;
      try {
        compressed = await VideoCompress.compressVideo(
          video.path,
          quality: VideoQuality.LowQuality,
          deleteOrigin: false,
        );
      } catch (e) {
        compressed = null;
      }
      if (compressed != null && compressed.file != null) {
        file = compressed.file!;
      }
      var bytes = await file.readAsBytes();
      if (bytes.length > 900 * 1024) {
        return {'error': 'Video could not be compressed below 900KB and cannot be uploaded.'};
      }
      final base64 = base64Encode(bytes);
      return {
        'base64': base64,
        'name': path.basename(file.path),
        'type': path.extension(file.path),
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