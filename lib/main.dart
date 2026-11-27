import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'network/trusted_roots.dart';
import 'pages/interaction_review_page.dart';
import 'pages/thread_review_page.dart';
import 'di.dart';
import 'core/frame_metrics.dart';
import 'core/app_log.dart';
import 'core/process_text_warmup.dart';
import 'core/startup_idle.dart';
import 'core/touch_sampling.dart';
import 'data/editorial_cover_cache.dart';
import 'parser/parser_worker.dart';

Future<void> main() async {
  HttpOverrides.global = ChhHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  TouchSampling(frames: 2);
  FrameMetrics.install();
  await editorialCoverCache.load();
  await setupDependencies();
  // 先恢复外观避免首帧闪色;超时不阻塞启动,读完仍会通知主题更新。
  await appearance.load().timeout(
    const Duration(milliseconds: 300),
    onTimeout: () {},
  );
  await readingPrefs.load().timeout(
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
  if (!review && !threadReview) {
    unawaited(warmPlatformTextActions());
    unawaited(_warmParser());
  }
}

Future<void> _warmParser() async {
  await waitForStartupIdle();
  try {
    await prewarmParserWorker();
  } catch (error) {
    AppLog.w('BOOT', '解析预热失败 ${error.runtimeType}');
  }
}
