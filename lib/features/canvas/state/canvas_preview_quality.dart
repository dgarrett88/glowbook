import 'dart:math' as math;
import 'dart:ui';

enum CanvasPreviewQuality {
  auto,
  p360,
  p480,
  p720,
  p1080,
  native,
}

extension CanvasPreviewQualityX on CanvasPreviewQuality {
  String get label {
    switch (this) {
      case CanvasPreviewQuality.auto:
        return 'Auto';
      case CanvasPreviewQuality.p360:
        return '360p';
      case CanvasPreviewQuality.p480:
        return '480p';
      case CanvasPreviewQuality.p720:
        return '720p';
      case CanvasPreviewQuality.p1080:
        return '1080p';
      case CanvasPreviewQuality.native:
        return 'Native';
    }
  }

  double? get targetLongestPhysicalSide {
    switch (this) {
      case CanvasPreviewQuality.auto:
        return 1920.0; // safe v1 default: roughly 1080p preview
      case CanvasPreviewQuality.p360:
        return 640.0;
      case CanvasPreviewQuality.p480:
        return 854.0;
      case CanvasPreviewQuality.p720:
        return 1280.0;
      case CanvasPreviewQuality.p1080:
        return 1920.0;
      case CanvasPreviewQuality.native:
        return null;
    }
  }
}

class CanvasPreviewMetrics {
  final CanvasPreviewQuality quality;
  final Size fullLogicalSize;
  final double devicePixelRatio;
  final double logicalScale;
  final int renderWidthPx;
  final int renderHeightPx;
  final int nativeWidthPx;
  final int nativeHeightPx;

  const CanvasPreviewMetrics({
    required this.quality,
    required this.fullLogicalSize,
    required this.devicePixelRatio,
    required this.logicalScale,
    required this.renderWidthPx,
    required this.renderHeightPx,
    required this.nativeWidthPx,
    required this.nativeHeightPx,
  });

  bool get isNative => logicalScale >= 0.999;

  String get shortLabel => '${quality.label} ${renderWidthPx}x$renderHeightPx';
}

CanvasPreviewMetrics computeCanvasPreviewMetrics({
  required Size fullLogicalSize,
  required double devicePixelRatio,
  required CanvasPreviewQuality quality,
}) {
  final safeWidth = math.max(1.0, fullLogicalSize.width);
  final safeHeight = math.max(1.0, fullLogicalSize.height);

  final nativeWidthPx = (safeWidth * devicePixelRatio).round();
  final nativeHeightPx = (safeHeight * devicePixelRatio).round();

  final nativeLongest = math.max(nativeWidthPx, nativeHeightPx).toDouble();
  final targetLongest = quality.targetLongestPhysicalSide;

  double logicalScale;

  if (targetLongest == null || nativeLongest <= 0) {
    logicalScale = 1.0;
  } else {
    logicalScale = targetLongest / nativeLongest;
    logicalScale = logicalScale.clamp(0.10, 1.0).toDouble();
  }

  final renderWidthPx =
      math.max(1, (safeWidth * logicalScale * devicePixelRatio).round());
  final renderHeightPx =
      math.max(1, (safeHeight * logicalScale * devicePixelRatio).round());

  return CanvasPreviewMetrics(
    quality: quality,
    fullLogicalSize: Size(safeWidth, safeHeight),
    devicePixelRatio: devicePixelRatio,
    logicalScale: logicalScale,
    renderWidthPx: renderWidthPx,
    renderHeightPx: renderHeightPx,
    nativeWidthPx: nativeWidthPx,
    nativeHeightPx: nativeHeightPx,
  );
}
