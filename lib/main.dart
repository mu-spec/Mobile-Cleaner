import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Flutter's default image cache is 100 MB, sized for photo galleries that
  // display large images. This app shows hundreds of small thumbnails, so a
  // smaller ceiling leaves far more headroom on a low-memory phone while
  // still holding every thumbnail a long scroll can produce.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 24 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 400;

  runApp(const ProviderScope(child: MobileCleanerApp()));
}
