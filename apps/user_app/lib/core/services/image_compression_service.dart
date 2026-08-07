import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../utils/app_logger.dart';

/// Compresses captured/selected images (KYC documents, selfies) before they are
/// persisted to a draft or queued for upload, keeping the offline queue small.
class ImageCompressionService {
  const ImageCompressionService();

  /// Compress the image at [sourcePath] to roughly [targetKb] KB by stepping
  /// JPEG quality down. Returns the compressed file path, or the original path
  /// if compression is unavailable or fails (so the flow always proceeds).
  Future<String> compress(String sourcePath, {int targetKb = 300}) async {
    final source = File(sourcePath);
    if (!await source.exists()) return sourcePath;

    final dir = source.parent.path;
    final dest =
        '$dir/vs_cmp_${source.uri.pathSegments.last}.jpg'.replaceAll(' ', '_');

    try {
      var quality = 85;
      String? bestPath;
      for (var attempt = 0; attempt < 4; attempt++) {
        final result = await FlutterImageCompress.compressAndGetFile(
          sourcePath,
          dest,
          quality: quality,
          minWidth: 1080,
          minHeight: 1080,
          format: CompressFormat.jpeg,
        );
        if (result == null) break;
        bestPath = result.path;
        final bytes = await File(result.path).length();
        if (bytes <= targetKb * 1024 || quality <= 35) break;
        quality -= 20;
      }
      return bestPath ?? sourcePath;
    } catch (e) {
      AppLogger.w('Image compression failed: $e');
      return sourcePath;
    }
  }
}
