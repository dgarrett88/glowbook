// lib/core/models/canvas_text_object.dart
import 'dart:ui' show Offset, TextAlign;

enum CanvasTextGlowMode {
  fullShape,
  edgeShape,
}

enum CanvasTextModDistribution {
  wholeText,
  perCharacter,
}

enum CanvasTextWaveDirection {
  leftToRight,
  rightToLeft,
  centerOut,
  outsideIn,
}

/// Editable text object stored in a canvas document.
///
/// V1 intent:
/// - one saved object with editable text
/// - can render as a whole word/object
/// - can later distribute LFO modulation per character without detaching letters
class CanvasTextObject {
  final String id;
  final String layerId;

  final String text;
  final Offset position;
  final double scale;

  /// Radians, matching the rest of the canvas transform system.
  final double rotation;

  /// 0..1
  final double opacity;

  final String? fontFamily;
  final double fontSize;
  final double letterSpacing;
  final double lineHeight;
  final TextAlign textAlign;

  /// ARGB int, same style as the rest of the app palette/storage.
  final int fillColor;
  final bool fillEnabled;

  final bool outlineEnabled;
  final int outlineColor;
  final double outlineWidth;
  final double outlineOpacity;

  final bool glowEnabled;
  final int glowColor;
  final double glowRadius;
  final double glowOpacity;
  final double glowBrightness;
  final CanvasTextGlowMode glowMode;

  /// Separate from outline: this is for light emitted from glyph edges.
  final bool edgeGlowEnabled;
  final double edgeGlowWidth;
  final double edgeGlowStrength;

  /// Keep this as a string so it can map to your existing glow/blend helpers.
  final String blendModeKey;

  /// Future LFO/distribution behaviour. Stored now so save files are ready.
  final CanvasTextModDistribution modDistribution;
  final double letterPhaseOffset;
  final CanvasTextWaveDirection waveDirection;
  final double letterRandomness;

  const CanvasTextObject({
    required this.id,
    required this.layerId,
    required this.text,
    this.position = Offset.zero,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.fontFamily,
    this.fontSize = 72.0,
    this.letterSpacing = 0.0,
    this.lineHeight = 1.0,
    this.textAlign = TextAlign.center,
    this.fillColor = 0xFFFFFFFF,
    this.fillEnabled = true,
    this.outlineEnabled = false,
    this.outlineColor = 0xFF000000,
    this.outlineWidth = 0.0,
    this.outlineOpacity = 1.0,
    this.glowEnabled = true,
    this.glowColor = 0xFF00FFFF,
    this.glowRadius = 18.0,
    this.glowOpacity = 0.75,
    this.glowBrightness = 1.0,
    this.glowMode = CanvasTextGlowMode.fullShape,
    this.edgeGlowEnabled = false,
    this.edgeGlowWidth = 2.0,
    this.edgeGlowStrength = 0.75,
    this.blendModeKey = 'additive',
    this.modDistribution = CanvasTextModDistribution.wholeText,
    this.letterPhaseOffset = 0.08,
    this.waveDirection = CanvasTextWaveDirection.leftToRight,
    this.letterRandomness = 0.0,
  });

  CanvasTextObject copyWith({
    String? id,
    String? layerId,
    String? text,
    Offset? position,
    double? scale,
    double? rotation,
    double? opacity,
    String? fontFamily,
    bool clearFontFamily = false,
    double? fontSize,
    double? letterSpacing,
    double? lineHeight,
    TextAlign? textAlign,
    int? fillColor,
    bool? fillEnabled,
    bool? outlineEnabled,
    int? outlineColor,
    double? outlineWidth,
    double? outlineOpacity,
    bool? glowEnabled,
    int? glowColor,
    double? glowRadius,
    double? glowOpacity,
    double? glowBrightness,
    CanvasTextGlowMode? glowMode,
    bool? edgeGlowEnabled,
    double? edgeGlowWidth,
    double? edgeGlowStrength,
    String? blendModeKey,
    CanvasTextModDistribution? modDistribution,
    double? letterPhaseOffset,
    CanvasTextWaveDirection? waveDirection,
    double? letterRandomness,
  }) {
    return CanvasTextObject(
      id: id ?? this.id,
      layerId: layerId ?? this.layerId,
      text: text ?? this.text,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
      fontSize: fontSize ?? this.fontSize,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      textAlign: textAlign ?? this.textAlign,
      fillColor: fillColor ?? this.fillColor,
      fillEnabled: fillEnabled ?? this.fillEnabled,
      outlineEnabled: outlineEnabled ?? this.outlineEnabled,
      outlineColor: outlineColor ?? this.outlineColor,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      outlineOpacity: outlineOpacity ?? this.outlineOpacity,
      glowEnabled: glowEnabled ?? this.glowEnabled,
      glowColor: glowColor ?? this.glowColor,
      glowRadius: glowRadius ?? this.glowRadius,
      glowOpacity: glowOpacity ?? this.glowOpacity,
      glowBrightness: glowBrightness ?? this.glowBrightness,
      glowMode: glowMode ?? this.glowMode,
      edgeGlowEnabled: edgeGlowEnabled ?? this.edgeGlowEnabled,
      edgeGlowWidth: edgeGlowWidth ?? this.edgeGlowWidth,
      edgeGlowStrength: edgeGlowStrength ?? this.edgeGlowStrength,
      blendModeKey: blendModeKey ?? this.blendModeKey,
      modDistribution: modDistribution ?? this.modDistribution,
      letterPhaseOffset: letterPhaseOffset ?? this.letterPhaseOffset,
      waveDirection: waveDirection ?? this.waveDirection,
      letterRandomness: letterRandomness ?? this.letterRandomness,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'layerId': layerId,
        'text': text,
        'x': position.dx,
        'y': position.dy,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'letterSpacing': letterSpacing,
        'lineHeight': lineHeight,
        'textAlign': textAlign.name,
        'fillColor': fillColor,
        'fillEnabled': fillEnabled,
        'outlineEnabled': outlineEnabled,
        'outlineColor': outlineColor,
        'outlineWidth': outlineWidth,
        'outlineOpacity': outlineOpacity,
        'glowEnabled': glowEnabled,
        'glowColor': glowColor,
        'glowRadius': glowRadius,
        'glowOpacity': glowOpacity,
        'glowBrightness': glowBrightness,
        'glowMode': glowMode.name,
        'edgeGlowEnabled': edgeGlowEnabled,
        'edgeGlowWidth': edgeGlowWidth,
        'edgeGlowStrength': edgeGlowStrength,
        'blendModeKey': blendModeKey,
        'modDistribution': modDistribution.name,
        'letterPhaseOffset': letterPhaseOffset,
        'waveDirection': waveDirection.name,
        'letterRandomness': letterRandomness,
      };

  factory CanvasTextObject.fromJson(Map<String, dynamic> json) {
    return CanvasTextObject(
      id: json['id'] as String? ?? _fallbackId(),
      layerId: json['layerId'] as String? ?? 'layer-main',
      text: json['text'] as String? ?? '',
      position: Offset(
        (json['x'] as num?)?.toDouble() ?? 0.0,
        (json['y'] as num?)?.toDouble() ?? 0.0,
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 72.0,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.0,
      textAlign: _enumByName(
        TextAlign.values,
        json['textAlign'] as String?,
        TextAlign.center,
      ),
      fillColor: (json['fillColor'] as int?) ?? 0xFFFFFFFF,
      fillEnabled: (json['fillEnabled'] as bool?) ?? true,
      outlineEnabled: (json['outlineEnabled'] as bool?) ?? false,
      outlineColor: (json['outlineColor'] as int?) ?? 0xFF000000,
      outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 0.0,
      outlineOpacity: (json['outlineOpacity'] as num?)?.toDouble() ?? 1.0,
      glowEnabled: (json['glowEnabled'] as bool?) ?? true,
      glowColor: (json['glowColor'] as int?) ?? 0xFF00FFFF,
      glowRadius: (json['glowRadius'] as num?)?.toDouble() ?? 18.0,
      glowOpacity: (json['glowOpacity'] as num?)?.toDouble() ?? 0.75,
      glowBrightness: (json['glowBrightness'] as num?)?.toDouble() ?? 1.0,
      glowMode: _enumByName(
        CanvasTextGlowMode.values,
        json['glowMode'] as String?,
        CanvasTextGlowMode.fullShape,
      ),
      edgeGlowEnabled: (json['edgeGlowEnabled'] as bool?) ?? false,
      edgeGlowWidth: (json['edgeGlowWidth'] as num?)?.toDouble() ?? 2.0,
      edgeGlowStrength: (json['edgeGlowStrength'] as num?)?.toDouble() ?? 0.75,
      blendModeKey: json['blendModeKey'] as String? ?? 'additive',
      modDistribution: _enumByName(
        CanvasTextModDistribution.values,
        json['modDistribution'] as String?,
        CanvasTextModDistribution.wholeText,
      ),
      letterPhaseOffset:
          (json['letterPhaseOffset'] as num?)?.toDouble() ?? 0.08,
      waveDirection: _enumByName(
        CanvasTextWaveDirection.values,
        json['waveDirection'] as String?,
        CanvasTextWaveDirection.leftToRight,
      ),
      letterRandomness: (json['letterRandomness'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  static String _fallbackId() =>
      'text_${DateTime.now().microsecondsSinceEpoch}';
}
