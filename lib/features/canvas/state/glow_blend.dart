import 'package:flutter/foundation.dart';

enum GlowBlend { additive, screen }

class GlowBlendState extends ChangeNotifier {
  GlowBlend _mode = GlowBlend.additive;
  GlowBlendState._();
  static final GlowBlendState I = GlowBlendState._();
  GlowBlend get mode => _mode;
  void setMode(GlowBlend m){
    if (_mode == m) return;
    _mode = m;
    notifyListeners();
  }
}
