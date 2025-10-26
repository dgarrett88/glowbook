
GlowBook — Sprint 1 fixed drop (based on pointer_toggle baseline)

Changes kept minimal to avoid compile errors:

- Added spline.dart and imported in LiquidNeon brush (currently falls back to polyline path for stability).
- Wired gestures in CanvasScreen to controller.pointerDown/Move/Up (no new method names introduced).
- Wrapped canvas in RepaintBoundary with a GlobalKey.
- TopToolbar now accepts optional onExport callback; CanvasScreen implements PNG capture and shows a SnackBar.
- BottomDock size slider calls controller.setBrushSize; color chip opens controller.pickColor(context).

Export note: bytes are captured; wire path_provider to save them to a file in GB-008 final step.
