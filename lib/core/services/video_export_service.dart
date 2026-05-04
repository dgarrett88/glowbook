import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/canvas/state/canvas_controller.dart';
import 'gallery_saver.dart';

class VideoExportCancelledException implements Exception {
  const VideoExportCancelledException();

  @override
  String toString() => 'Video export cancelled';
}

class VideoExportCancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

class VideoExportProgressInfo {
  final double progress;
  final String stage;
  final int completedFrames;
  final int totalFrames;
  final Duration elapsed;
  final Duration? eta;

  const VideoExportProgressInfo({
    required this.progress,
    required this.stage,
    required this.completedFrames,
    required this.totalFrames,
    required this.elapsed,
    required this.eta,
  });
}

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

class VideoExportAspectOption {
  final String label;
  final double? widthRatio;
  final double? heightRatio;

  const VideoExportAspectOption({
    required this.label,
    required this.widthRatio,
    required this.heightRatio,
  });

  bool get usesCurrentCanvasAspect => widthRatio == null || heightRatio == null;

  static const current = VideoExportAspectOption(
    label: 'Current',
    widthRatio: null,
    heightRatio: null,
  );

  static const square = VideoExportAspectOption(
    label: 'Square 1:1',
    widthRatio: 1,
    heightRatio: 1,
  );

  static const portrait = VideoExportAspectOption(
    label: 'Portrait 9:16',
    widthRatio: 9,
    heightRatio: 16,
  );

  static const landscape = VideoExportAspectOption(
    label: 'Landscape 16:9',
    widthRatio: 16,
    heightRatio: 9,
  );

  static const values = [
    current,
    square,
    portrait,
    landscape,
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
    required VideoExportAspectOption aspectOption,
    required VideoExportFpsOption fpsOption,
    required double durationSec,
    VideoExportCancelToken? cancelToken,
    void Function(double progress)? onProgress,
    void Function(VideoExportProgressInfo info)? onProgressInfo,
  }) async {
    final safeDurationSec = durationSec.clamp(1.0, 60.0).toDouble();
    final fps = fpsOption.fps;
    final totalFrames = (safeDurationSec * fps).round();
    final longestSidePx = options.longestSidePx;

    final sourceSize = controller.canvasSize;
    if (sourceSize.width <= 0 || sourceSize.height <= 0) {
      throw StateError('Canvas size is not ready yet.');
    }

    final outputSize = aspectOption.usesCurrentCanvasAspect
        ? _fitCurrentAspectToLongestSide(
            sourceSize: sourceSize,
            longestSidePx: longestSidePx,
          )
        : _fitAspectToLongestSide(
            widthRatio: aspectOption.widthRatio!,
            heightRatio: aspectOption.heightRatio!,
            longestSidePx: longestSidePx,
          );

    final tempRoot = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final exportDir = Directory('${tempRoot.path}/glowbook_export_$stamp');
    await exportDir.create(recursive: true);

    final outputMp4Path = '${exportDir.path}/GlowBook_$stamp.mp4';

    final stopwatch = Stopwatch()..start();

    void emitProgress({
      required double progress,
      required String stage,
      required int completedFrames,
      Duration? eta,
    }) {
      final p = progress.clamp(0.0, 1.0).toDouble();

      onProgress?.call(p);

      onProgressInfo?.call(
        VideoExportProgressInfo(
          progress: p,
          stage: stage,
          completedFrames: completedFrames,
          totalFrames: totalFrames,
          elapsed: stopwatch.elapsed,
          eta: eta,
        ),
      );
    }

    try {
      for (int i = 0; i < totalFrames; i++) {
        if (cancelToken?.isCancelled == true) {
          throw const VideoExportCancelledException();
        }

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

        final completed = i + 1;
        Duration? eta;

        final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
        if (elapsedSeconds >= 3.0 && completed > 0) {
          final framesPerSecond = completed / elapsedSeconds;
          if (framesPerSecond > 0) {
            final remainingFrames = totalFrames - completed;
            eta = Duration(
              milliseconds:
                  ((remainingFrames / framesPerSecond) * 1000).round(),
            );
          }
        }

        emitProgress(
          progress: completed / totalFrames * 0.80,
          stage: 'Rendering frames',
          completedFrames: completed,
          eta: eta,
        );
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

      emitProgress(
        progress: 0.92,
        stage: 'Encoding video',
        completedFrames: totalFrames,
        eta: null,
      );

      final mp4Bytes = await File(outputMp4Path).readAsBytes();

      final savedUri = await GallerySaverService.saveMp4ToGallery(
        mp4Bytes,
        filename:
            'GlowBook_${options.label}_${aspectOption.label.replaceAll(' ', '')}_${fpsOption.fps}fps_$stamp.mp4',
      );

      emitProgress(
        progress: 1.0,
        stage: 'Saved',
        completedFrames: totalFrames,
        eta: Duration.zero,
      );
      return savedUri;
    } finally {
      // Clean temp PNG frames and temp MP4.
      if (await exportDir.exists()) {
        await exportDir.delete(recursive: true);
      }
    }
  }

  static Size _fitAspectToLongestSide({
    required double widthRatio,
    required double heightRatio,
    required int longestSidePx,
  }) {
    if (widthRatio <= 0 || heightRatio <= 0) {
      return Size(longestSidePx.toDouble(), longestSidePx.toDouble());
    }

    final aspect = widthRatio / heightRatio;

    int outW;
    int outH;

    if (widthRatio >= heightRatio) {
      outW = longestSidePx;
      outH = (longestSidePx / aspect).round();
    } else {
      outH = longestSidePx;
      outW = (longestSidePx * aspect).round();
    }

    // H.264 encoders prefer even dimensions.
    if (outW.isOdd) outW += 1;
    if (outH.isOdd) outH += 1;

    outW = outW.clamp(2, 8192);
    outH = outH.clamp(2, 8192);

    return Size(outW.toDouble(), outH.toDouble());
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
