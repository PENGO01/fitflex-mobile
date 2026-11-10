import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Renders the widget under [boundaryKey] (a [RepaintBoundary]) to a PNG at
/// [pixelRatio] times its logical size. Null when it is not on screen yet.
/// Shared by the event medal / reward cards and the vendor receipt image.
Future<Uint8List?> capturePng(
  GlobalKey boundaryKey, {
  double pixelRatio = 3,
}) async {
  final ctx = boundaryKey.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject();
  if (box is! RenderRepaintBoundary) return null;
  final image = await box.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}
