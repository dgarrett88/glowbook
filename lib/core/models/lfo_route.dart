// lib/core/models/lfo_route.dart

import 'dart:convert';

/// Which target param the LFO modulates.
/// Add more entries as you expose more knobs.
enum LfoParam {
  // Layer params
  layerX,
  layerY,
  layerScale,
  layerRotationDeg,
  layerOpacity,

  // Stroke params
  strokeSize,
  strokeX,
  strokeY,
  strokeRotationDeg,
  strokeCoreOpacity,
  strokeGlowRadius,
  strokeGlowOpacity,
  strokeGlowBrightness,

  // Text object params
  textX,
  textY,
  textFontSize,
  textScale,
  textRotationDeg,
  textOpacity,
  textGlowRadius,
  textGlowOpacity,
  textGlowBrightness,
  textEdgeGlowWidth,
  textEdgeGlowStrength,
  textLetterPhaseOffset,
}

/// A routing from an LFO to some target (layer/stroke/whatever).
class LfoRoute {
  final String id;

  bool enabled;

  /// Which LFO drives this route.
  final String lfoId;

  /// Target: either a layer or a stroke depending on your design.
  final String layerId;

  /// Optional stroke target (null = layer/text target).
  final String? strokeId;

  /// Optional text object target.
  final String? textObjectId;

  /// If true, this route targets stroke params.
  final bool isStrokeTarget;

  /// If true, this route targets a text object param.
  final bool isTextTarget;

  final LfoParam param;

  /// Generic amount (used by non-rotation params).
  double amount;

  /// Rotation-specific amount in degrees (some of your code uses amountDeg).
  double amountDeg;

  /// If true, shaped value is [-1..1]; else [0..1].
  bool bipolar;

  LfoRoute({
    required this.id,
    this.enabled = true,
    required this.lfoId,
    required this.layerId,
    this.strokeId,
    this.textObjectId,
    this.isStrokeTarget = false,
    this.isTextTarget = false,
    required this.param,
    this.amount = 0.0,
    this.amountDeg = 0.0,
    this.bipolar = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'lfoId': lfoId,
        'layerId': layerId,
        'strokeId': strokeId,
        'textObjectId': textObjectId,
        'isStrokeTarget': isStrokeTarget,
        'isTextTarget': isTextTarget,
        'param': param.name,
        'amount': amount,
        'amountDeg': amountDeg,
        'bipolar': bipolar,
      };

  static LfoRoute fromJson(Map<String, dynamic> j) {
    final paramName = (j['param'] as String?) ?? 'layerRotationDeg';
    final parsedParam = LfoParam.values.firstWhere(
      (e) => e.name == paramName,
      orElse: () => LfoParam.layerRotationDeg,
    );

    return LfoRoute(
      id: (j['id'] as String?) ?? _fallbackId(),
      enabled: (j['enabled'] as bool?) ?? true,
      lfoId: (j['lfoId'] as String?) ?? '',
      layerId: (j['layerId'] as String?) ?? '',
      strokeId: j['strokeId'] as String?,
      textObjectId: j['textObjectId'] as String?,
      isStrokeTarget: (j['isStrokeTarget'] as bool?) ?? false,
      isTextTarget: (j['isTextTarget'] as bool?) ?? false,
      param: parsedParam,
      amount: (j['amount'] as num?)?.toDouble() ?? 0.0,
      amountDeg: (j['amountDeg'] as num?)?.toDouble() ?? 0.0,
      bipolar: (j['bipolar'] as bool?) ?? true,
    );
  }

  static String _fallbackId() {
    // non-crypto unique-ish id; replace with your real id generator if you have one
    final ms = DateTime.now().microsecondsSinceEpoch;
    return base64Url.encode(utf8.encode('r$ms')).replaceAll('=', '');
  }

  LfoRoute copyWith({
    String? id,
    bool? enabled,
    String? lfoId,
    String? layerId,
    String? strokeId,
    String? textObjectId,
    bool? isStrokeTarget,
    bool? isTextTarget,
    LfoParam? param,
    double? amount,
    double? amountDeg,
    bool? bipolar,
  }) {
    return LfoRoute(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      lfoId: lfoId ?? this.lfoId,
      layerId: layerId ?? this.layerId,
      strokeId: strokeId ?? this.strokeId,
      textObjectId: textObjectId ?? this.textObjectId,
      isStrokeTarget: isStrokeTarget ?? this.isStrokeTarget,
      isTextTarget: isTextTarget ?? this.isTextTarget,
      param: param ?? this.param,
      amount: amount ?? this.amount,
      amountDeg: amountDeg ?? this.amountDeg,
      bipolar: bipolar ?? this.bipolar,
    );
  }
}
