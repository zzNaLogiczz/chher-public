/// Explicit offline profile target. Production delivery uses lib/main.dart.
library;

import 'package:flutter/material.dart';
import 'package:chh_app/core/frame_metrics.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/typography.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/pages/thread_detail_page.dart';
import 'package:chh_app/ui/app_button.dart';
import 'package:chh_app/widgets/image_stack_gallery.dart';

const _origin = String.fromEnvironment(
  'stack_review_origin',
  defaultValue: 'http://127.0.0.1:18772',
);
String _photo(String name) => '$_origin/$name.png';
List<String> _group(String prefix, int count) => [
  for (var i = 1; i <= count; i++) _photo('${prefix}_$i'),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FrameMetrics.install();
  runApp(const _Review());
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool _dark = false;
  bool _thread = false;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAppTheme(_dark ? Brightness.dark : Brightness.light),
    home: _thread ? _threadPage() : const _Stage(),
    builder: (context, child) => Column(
      children: [
        Material(
          color: AppTokens.of(context).surface,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '离线样例 / 不会发送到论坛',
                      style: AppType.footnote.copyWith(
                        color: AppTokens.of(context).text2,
                      ),
                    ),
                  ),
                ),
                AppButton(
                  label: _thread ? '叠卡' : '正文',
                  small: true,
                  variant: AppButtonVariant.plain,
                  onPressed: () => setState(() => _thread = !_thread),
                ),
                AppButton(
                  label: _dark ? '浅色' : '深色',
                  small: true,
                  variant: AppButtonVariant.plain,
                  onPressed: () => setState(() => _dark = !_dark),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child!),
      ],
    ),
  );
}

class _Stage extends StatelessWidget {
  const _Stage();
  @override
  Widget build(BuildContext context) {
    final urls = [
      _photo('mixed_landscape'),
      _photo('mixed_portrait'),
      _photo('extreme_portrait'),
      ..._group('g1', 3),
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            ImageStackGallery(
              key: const PageStorageKey('review-primary-stack'),
              urls: urls,
              gallery: urls,
              galleryStartIndex: 0,
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.only(left: 42),
              child: ImageStackGallery(
                key: const PageStorageKey('review-compact-stack'),
                urls: _group('r1', 3),
                gallery: _group('r1', 3),
                galleryStartIndex: 0,
                compact: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ThreadDetailPage _threadPage() => ThreadDetailPage(
  tid: 999991,
  title: '离线样例：连续图片叠卡',
  loadPage: (_, _, _) async => ThreadDetail(
    tid: 999991,
    fid: 290,
    title: '离线样例：连续图片叠卡',
    posts: [
      Post(
        pid: 1,
        floor: 1,
        author: '主楼样例作者',
        timeRaw: '2026-11-04',
        content: [
          const TextBlock('主楼样例：连续五张开箱图片。'),
          for (final url in _group('g1', 5)) ImageBlock(url),
          const TextBlock('原帖文字保留，下一张单独展示。'),
          ImageBlock(_photo('single_airflow')),
          const TextBlock('文字之后是另一段连续四张细节。'),
          for (final url in _group('g2', 4)) ImageBlock(url),
        ],
      ),
      Post(
        pid: 2,
        floor: 2,
        author: '回复样例作者',
        timeRaw: '2026-11-04',
        content: [
          const TextBlock('回复连续三张图，使用紧凑叠卡。'),
          for (final url in _group('r1', 3)) ImageBlock(url),
        ],
      ),
      Post(
        pid: 3,
        floor: 3,
        author: '长回复样例作者',
        timeRaw: '2026-11-04',
        content: [
          const TextBlock('千张图片惰性展示验收，不会一次性解码。'),
          for (var i = 0; i < 1000; i++)
            ImageBlock('${_photo('g1_${i % 5 + 1}')}?frame=$i'),
        ],
      ),
    ],
    page: const PageInfo(current: 1, hasNext: false),
  ),
);
