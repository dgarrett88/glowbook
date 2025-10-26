import 'dart:ui';
import '../../../core/models/stroke.dart';

Path strokeToPath(List<PointSample> pts){
  final path = Path();
  if(pts.isEmpty) return path;
  path.moveTo(pts.first.x, pts.first.y);
  for (var i=1;i<pts.length;i++){
    path.lineTo(pts[i].x, pts[i].y);
  }
  return path;
}
