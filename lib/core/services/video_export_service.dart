import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/canvas/state/canvas_controller.dart';
import 'gallery_saver.dart';

class VideoExportOptions {
  final String label;
  final int longestSidePx;

  const VideoExportOptions({
    required this.label,
    required this.longestSidePx,
  });

  static const p360 = VideoExportOptions(label: '360p', longestSidePx: 640);
  static const p480 = VideoExportOptions(label: '480p', longestSidePx: 854);
  static const p720 = VideoExportOptions(label: '720p', longestSidePx: 1280);
  static const p1080 = VideoExportOptions(label: '1080p', longestSidePx: 1920);
  static const p1440 = VideoExportOptions(label: '1440p', longestSidePx: 2560);
  static const p4k = VideoExportOptions(label: '4K', longestSidePx: 3840);
static const p8k = VideoExportOptions(label: '8K', longestSidePx: 7680);

static const values = [
  p360,
  p480,
  p720,
  p1080,
  p1440,
  p4k,
];
}

class VideoExportFpsOption {
  final String label;
  final int fps;

  const VideoExportFpsOption({
    required this.label,
    required this.fps,
  });

  static const fps30 = VideoExportFpsOption(label: '30 FPS', fps: 30);
  static const fps60 = VideoExportFpsOption(label: '60 FPS', fps: 60);

  static const values = [
    fps30,
    fps60,
  ];
}

class VideoExportService {
static Future<String?> exportCurrentCanvasVideo({
  required CanvasController controller,
  required VideoExportOptions options,
  required VideoExportFpsOption fpsOption,
  void Function(double progress)? onProgress,
}) async {
const durationSec = 5.0;
final fps = fpsOption.fps;
final totalFrames = (durationSec * fps).round();
final longestSidePx = options.longestSidePx;

    final sourceSize = controller.canvasSize;
    if (sourceSize.width <= 0 || sourceSize.height <= 0) {
      throw StateError('Canvas size is not ready yet.');
    }

    final outputSize = _fitCurrentAspectToLongestSide(
      sourceSize: sourceSize,
      longestSidePx: longestSidePx,
    );

    final tempRoot = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final exportDir = Directory('${tempRoot.path}/glowbook_export_$stamp');
    await exportDir.create(recursive: true);

    final outputMp4Path = '${exportDir.path}/GlowBook_$stamp.mp4';

    try {
      for (int i = 0; i < totalFrames; i++) {
        final timeSec = i / fps;

        final bytes = await controller.renderExportPngFrame(
          outputSizePx: outputSize,
          timeSec: timeSec,
        );

        if (bytes == null) {
          throw StateError('Failed to render frame $i.');
        }

        final framePath =
            '${exportDir.path}/frame_${i.toString().padLeft(5, '0')}.png';

        await File(framePath).writeAsBytes(bytes, flush: false);

        onProgress?.call((i + 1) / totalFrames * 0.80);
      }

      final inputPattern = '${exportDir.path}/frame_%05d.png';

      // H.264 MP4 for social media.
      // yuv420p keeps it compatible with most apps/sites.
final command = [
  '-y',
  '-framerate $fps',
  '-i "$inputPattern"',
  '-c:v libx264',
  '-pix_fmt yuv420p',
  '-profile:v high',
  '-crf 12',
  '-preset slow',
  '-movflags +faststart',
  '"$outputMp4Path"',
].join(' ');
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw StateError('FFmpeg export failed: $logs');
      }

      onProgress?.call(0.92);

      final mp4Bytes = await File(outputMp4Path).readAsBytes();

      final savedUri = await GallerySaverService.saveMp4ToGallery(
        mp4Bytes,
   filename: 'GlowBook_${options.label}_${fpsOption.fps}fps_$stamp.mp4',
      );

      onProgress?.call(1.0);

      return savedUri;
    } finally {
      // Clean temp PNG frames and temp MP4.
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true);
      }
    }
  }

  static Size _fitCurrentAspectToLongestSide({
    required Size sourceSize,
    required int longestSidePx,
  }) {
    final w = sourceSize.width;
    final h = sourceSize.height;

    if (w <= 0 || h <= 0) {
      return const Size(1440, 1440);
    }

    final longest = math.max(w, h);
    final scale = longestSidePx / longest;

    int outW = (w * scale).round();
    int outH = (h * scale).round();

    // H.264 encoders prefer even dimensions.
    if (outW.isOdd) outW += 1;
    if (outH.isOdd) outH += 1;

    outW = outW.clamp(2, 8192);
    outH = outH.clamp(2, 8192);

    return Size(outW.toDouble(), outH.toDouble());
  }
}