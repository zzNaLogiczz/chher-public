/// A searchable diagnostic stream; all content stays within the application.
library;

import 'dart:io';
import '../ui/app_button.dart';
import '../design/typography.dart';
import 'package:flutter/material.dart';
import '../ui/feedback.dart';
import '../ui/segmented.dart';
import '../ui/chrome_button.dart';
import '../ui/picker.dart';
import 'package:flutter/services.dart';
import '../core/app_log.dart';
import '../design/tokens.dart';
import '../widgets/state_view.dart';
import '../widgets/browse_controls.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/large_title_scaffold.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});
  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  bool _onlyProblems = false;
  String _query = '';
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LogEntry> get _visible => AppLog.instance.entries.reversed
      .where(
        (entry) =>
            (!_onlyProblems || entry.level != LogLevel.info) &&
            (_query.isEmpty ||
                '${entry.tag} ${entry.message}'.toLowerCase().contains(
                  _query.toLowerCase(),
                )),
      )
      .toList();
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return LargeTitleScaffold(
      title: '运行日志',
      surface: AppSurface.grouped,
      // 复制、导出、清空合进一个胶囊组
      actions: [
        ChromeGroup(
          items: [
            ChromeGroupItem(
              tooltip: '复制当前列表',
              icon: AppIcons.copy,
              onPressed: _copyVisible,
            ),
            ChromeGroupItem(
              tooltip: '导出全部日志',
              icon: AppIcons.export,
              onPressed: _export,
            ),
            ChromeGroupItem(
              tooltip: '清空日志',
              icon: AppIcons.trash,
              onPressed: _clear,
            ),
          ],
        ),
      ],
      body: AnimatedBuilder(
        animation: AppLog.instance,
        builder: (context, _) {
          final rows = _visible;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
                child: BrowseSearchField(
                  controller: _search,
                  hint: '搜索请求与结果',
                  onChanged: (value) => setState(() => _query = value.trim()),
                  onClear: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${rows.length} 条记录',
                      style: TextStyle(
                        fontSize: AppType.sizeFootnote,
                        color: t.text2,
                      ),
                    ),
                    AppSegmented<bool>(
                      compact: true,
                      fallbackTitle: '日志范围',
                      options: const [
                        PickerOption(value: false, label: '全部'),
                        PickerOption(value: true, label: '只看问题'),
                      ],
                      value: _onlyProblems,
                      onChanged: (value) =>
                          setState(() => _onlyProblems = value),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: rows.isEmpty
                    ? StateView.empty(
                        message: _query.isNotEmpty || _onlyProblems
                            ? '没有符合条件的日志'
                            : '还没有日志',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => Divider(
                          height: .5,
                          thickness: .5,
                          color: t.separator,
                        ),
                        itemBuilder: (context, i) => _LogRow(entry: rows[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyVisible() async {
    final rows = _visible;
    if (rows.isEmpty) {
      _toast('没有可复制的日志');
      return;
    }
    await Clipboard.setData(ClipboardData(text: rows.reversed.join('\n')));
    if (mounted) _toast('已复制当前列表');
  }

  Future<void> _export() async {
    try {
      final file = File(
        '${Directory.systemTemp.path}/chh-log-${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await file.writeAsString(AppLog.instance.dump());
      if (mounted) _toast('已导出 ${file.path}');
    } catch (_) {
      if (mounted) _toast('日志导出失败，请稍后重试');
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空运行日志？'),
        actions: [
          AppButton(
            label: '取消',
            variant: AppButtonVariant.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          AppButton(
            label: '清空',
            variant: AppButtonVariant.plain,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok == true) AppLog.instance.clear();
  }

  void _toast(String text) => AppToast.show(context, text);
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  const _LogRow({required this.entry});
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final issue = entry.level != LogLevel.info;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (entry.level) {
                  LogLevel.info => AppIcons.info,
                  LogLevel.warn => AppIcons.warning,
                  LogLevel.error => AppIcons.warning,
                },
                size: 17,
                color: issue ? t.warn : t.text3,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entry.tag,
                  style: TextStyle(
                    fontSize: AppType.sizeFootnote,
                    fontWeight: FontWeight.w600,
                    color: issue ? t.warn : t.text2,
                  ),
                ),
              ),
              Text(
                entry.timeText,
                style: TextStyle(
                  fontSize: AppType.sizeFootnote,
                  color: t.text3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          SelectableText(
            entry.message,
            style: TextStyle(
              fontSize: AppType.sizeFootnote,
              height: 1.75,
              color: t.text,
            ),
          ),
        ],
      ),
    );
  }
}
