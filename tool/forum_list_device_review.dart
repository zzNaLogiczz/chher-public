/// Explicit offline performance target; production builds use lib/main.dart.
library;

import 'package:flutter/material.dart';
import 'package:chh_app/core/frame_metrics.dart';
import 'package:chh_app/data/forum_repository.dart';
import 'package:chh_app/design/theme.dart';
import 'package:chh_app/design/tokens.dart';
import 'package:chh_app/design/typography.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/pages/forum_threads_page.dart';
import 'package:chh_app/ui/app_button.dart';

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
  final _repository = _Forums();
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAppTheme(_dark ? Brightness.dark : Brightness.light),
    home: ForumThreadsPage(
      fid: 999990,
      title: '版块列表验收',
      repository: _repository,
    ),
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
                      '离线样例 / 1000 条 / 不向论坛发送',
                      style: AppType.footnote.copyWith(
                        color: AppTokens.of(context).text2,
                      ),
                    ),
                  ),
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

class _Forums extends ForumRepository {
  _Forums() : super(ChhClient(fetchers: []));
  @override
  Future<List<ThreadType>> threadTypes(int fid, {bool refresh = false}) async =>
      const [
        ThreadType(typeid: 1, name: '硬件'),
        ThreadType(typeid: 2, name: '分享'),
      ];
  @override
  Future<ThreadListPage> threadList(
    int fid, {
    int page = 1,
    int? typeid,
    String? filter,
    String? orderby,
    bool refresh = false,
  }) async {
    final now = DateTime.now();
    return ThreadListPage(
      threads: [
        for (var i = 0; i < 1000; i++)
          ThreadSummary(
            tid: 990000 + i,
            title: i < 3 ? '置顶样例：版块阅读与交流规则 $i' : '本地样例 $i：装机体验、使用记录与日常分享',
            typeName: i.isEven ? '硬件' : '分享',
            author: '示例作者 $i',
            replies: i * 7,
            views: i * 70,
            sticky: i < 3,
            hasImages: i % 3 == 0,
            createdAt: now.subtract(Duration(days: i)),
            lastPostTimeRaw: now
                .subtract(Duration(minutes: i * 10))
                .toString()
                .split('.')
                .first,
          ),
      ],
      page: const PageInfo(current: 1, hasNext: false),
    );
  }
}
