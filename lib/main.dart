import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'network/trusted_roots.dart';
import 'pages/interaction_review_page.dart';
import 'pages/thread_review_page.dart';
import 'di.dart';
import 'core/frame_metrics.dart';
import 'data/editorial_cover_cache.dart';

Future<void> main() async {
  HttpOverrides.global = ChhHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  FrameMetrics.install();
  await editorialCoverCache.load();
  setupDependencies();
  // 先恢复外观避免首帧闪色;超时不阻塞启动,读完仍会通知主题更新。
  await appearance.load().timeout(
    const Duration(milliseconds: 300),
    onTimeout: () {},
  );
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
