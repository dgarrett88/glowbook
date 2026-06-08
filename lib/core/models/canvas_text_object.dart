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

/// Optional per-character overrides for text objects.
///
/// This lets the text object stay as one editable word while still allowing
/// individual letters to be pushed, scaled, rotated, faded, or glow-boosted.
/// It is intentionally index-based for now because the first text workflow is
/// short visual words/logos rather than paragraph editing.
class CanvasTextLetterOverride {
  final int index;
  final double offsetX;
  final double offsetY;
  final double scale;
  final double rotation;
  final double opacity;
  final double glowBoost;

  const CanvasTextLetterOverride({
    required this.index,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.glowBoost = 1.0,
  });

  CanvasTextLetterOverride copyWith({
    int? index,
    double? offsetX,
    double? offsetY,
    double? scale,
    double? rotation,
    double? opacity,
    double? glowBoost,
  }) {
    return CanvasTextLetterOverride(
      index: index ?? this.index,
      offsetX: offsetX ?? this.offsetX,
      offsetY: offsetY ?? this.offsetY,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      glowBoost: glowBoost ?? this.glowBoost,
    );
  }

  bool get isDefault =>
      offsetX == 0.0 &&
      offsetY == 0.0 &&
      scale == 1.0 &&
      rotation == 0.0 &&
      opacity == 1.0 &&
      glowBoost == 1.0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'index': index,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
        'glowBoost': glowBoost,
      };

  factory CanvasTextLetterOverride.fromJson(Map<String, dynamic> json) {
    return CanvasTextLetterOverride(
      index: (json['index'] as num?)?.toInt() ?? 0,
      offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0.0,
      offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      glowBoost: (json['glowBoost'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Editable text object stored in a canvas document.
///
/// V1 intent:
/// - one saved parent object with editable text
/// - parent controls edit the whole word/object
/// - optional letter overrides edit individual letters without detaching them
/// - LFO can later be distributed per character with phase offset
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

  /// Static per-letter edits. Whole-word params remain the parent.
  final List<CanvasTextLetterOverride> letterOverrides;

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
    this.letterOverrides = const [],
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
    List<CanvasTextLetterOverride>? letterOverrides,
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
      letterOverrides: letterOverrides ?? this.letterOverrides,
    );
  }

  CanvasTextLetterOverride letterOverrideAt(int index) {
    for (final override in letterOverrides) {
      if (override.index == index) return override;
    }
    return CanvasTextLetterOverride(index: index);
  }

  CanvasTextObject withLetterOverride(CanvasTextLetterOverride override) {
    final safe = override.index < 0 ? override.copyWith(index: 0) : override;
    final next = <CanvasTextLetterOverride>[];
    var replaced = false;

    for (final existing in letterOverrides) {
      if (existing.index == safe.index) {
        replaced = true;
        if (!safe.isDefault) next.add(safe);
      } else if (existing.index >= 0 && existing.index < text.length) {
        next.add(existing);
      }
    }

    if (!replaced && !safe.isDefault && safe.index < text.length) {
      next.add(safe);
    }

    next.sort((a, b) => a.index.compareTo(b.index));
    return copyWith(letterOverrides: next);
  }

  CanvasTextObject clearLetterOverride(int index) {
    return copyWith(
      letterOverrides: letterOverrides.where((o) => o.index != index).toList(),
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
        'letterOverrides': letterOverrides
            .where((o) => !o.isDefault)
            .map((o) => o.toJson())
            .toList(),
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
      letterOverrides: ((json['letterOverrides'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => CanvasTextLetterOverride.fromJson(
                Map<String, dynamic>.from(m),
              ))
          .where((o) => o.index >= 0)
          .toList(),
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
