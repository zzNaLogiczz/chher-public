import 'package:flutter/material.dart';

import 'app.dart';
import 'pages/interaction_review_page.dart';
import 'pages/thread_review_page.dart';
import 'di.dart';
import 'core/frame_metrics.dart';
import 'data/editorial_cover_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FrameMetrics.install();
  await editorialCoverCache.load();
  setupDependencies();
  const review = bool.fromEnvironment('interaction_review');
  const threadReview = bool.fromEnvironment('thread_review');
  runApp(
    threadReview
        ? const ThreadReviewApp()
        : review
        ? const InteractionReviewApp()
        : const ChhApp(),
  );
}
