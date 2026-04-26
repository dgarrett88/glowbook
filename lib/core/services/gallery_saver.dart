import 'package:flutter/services.dart';

class GallerySaverService {
  static const MethodChannel _ch = MethodChannel('glowbook/gallery');

  static Future<String?> savePngToGallery(
    List<int> bytes, {
    String? filename,
  }) async {
    final name =
        filename ?? 'GlowBook_${DateTime.now().millisecondsSinceEpoch}.png';

    final res = await _ch.invokeMethod<String>('saveImage', {
      'bytes': bytes,
      'filename': name,
      'mimeType': 'image/png',
      'relativePath': 'Pictures/GlowBook',
    });

    return res;
  }

  static Future<String?> saveMp4ToGallery(
    List<int> bytes, {
    String? filename,
  }) async {
    final name =
        filename ?? 'GlowBook_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final res = await _ch.invokeMethod<String>('saveVideo', {
      'bytes': bytes,
      'filename': name,
      'mimeType': 'video/mp4',
      'relativePath': 'Movies/GlowBook',
    });

    return res;
  }
}