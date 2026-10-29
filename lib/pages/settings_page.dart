/// Source-account settings remain read-only; diagnostics always stay reachable.
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';
import '../ui/segmented.dart';
import '../design/tokens.dart';
import '../ui/picker.dart';
import '../di.dart';
import '../data/image_disk_cache.dart';
import '../data/space_repository.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/expressive_controls.dart';
import '../models/models.dart';
import '../ui/grouped.dart';
import '../widgets/state_view.dart';
import '../update/update_controller.dart';
import '../core/app_info.dart';
import 'about_page.dart';
import 'log_page.dart';

class SettingsPage extends StatelessWidget {
  final SpaceRepository? repository;
  const SettingsPage({super.key, this.repository});
  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '设置',
    surface: AppSurface.grouped,
    body: SettingsBody(repository: repository),
  );
}

class SettingsBody extends StatefulWidget {
  final SpaceRepository? repository;
  const SettingsBody({super.key, this.repository});
  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  static const _labels = ['基本资料', '论坛信息', '隐私'];
  static const _ops = [
    ('profile', 'base'),
    ('profile', 'info'),
    ('privacy', 'base'),
  ];
  int _seg = 0;
  late Future<SettingsForm> _future = _load();
  // 缓存大小异步统计,算完前行上显示占位,不阻塞设置页出现
  String _cacheLabel = '计算中';
  Future<SettingsForm> _load() {
    final (ac, op) = _ops[_seg];
    return (widget.repository ?? spaceRepo).settings(ac: ac, op: op);
  }

  void _switch(int i) {
    if (i == _seg) return;
    setState(() {
      _seg = i;
      _future = _load();
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    final bytes = await imageDiskCache.totalBytes();
    if (mounted) setState(() => _cacheLabel = _formatBytes(bytes));
  }

  void _retry() => setState(() => _future = _load());

  /// 只读资料行:按网页上的显示规则取值
  Widget _fieldRow(SettingField field) {
    // privacy[x] 是同名资料的可见范围,不是第二个同名字段
    final title = field.name.startsWith('privacy[')
        ? '${field.label} 可见范围'
        : field.label;
    final hasValue = field.value?.isNotEmpty == true;
    final String value;
    if (field.options.isNotEmpty) {
      // 下拉框没有 selected 时,网页显示第一项
      value = hasValue ? field.value! : field.options.first;
    } else if (field.value == null) {
      // 复选框只有开关两种状态
      value = field.checked ? '已开启' : '未开启';
    } else {
      value = hasValue ? field.value! : '未填写';
    }
    return GroupedRow(title: title, value: value);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screen,
          4,
          AppSpace.screen,
          16,
        ),
        child: AppSegmented<int>(
          fallbackTitle: '设置',
          options: [
            for (var i = 0; i < _labels.length; i++)
              PickerOption(value: i, label: _labels[i]),
          ],
          value: _seg,
          onChanged: _switch,
        ),
      ),
      Expanded(
        child: FutureBuilder<SettingsForm>(
          future: _future,
          builder: (context, snap) {
            Widget content;
            if (snap.connectionState != ConnectionState.done) {
              content = SizedBox(height: 220, child: StateView.loading());
            } else if (snap.error is PageMessage) {
              content = SizedBox(
                height: 260,
                child: StateView.forMessage(
                  snap.error as PageMessage,
                  onLogin: () async {
                    await Navigator.of(context).pushNamed('/login');
                    if (mounted) _retry();
                  },
                ),
              );
            } else if (snap.error != null) {
              content = SizedBox(
                height: 260,
                child: StateView.error(snap.error!, onRetry: _retry),
              );
            } else if (snap.data!.fields.isEmpty) {
              content = SizedBox(
                height: 220,
                child: StateView.empty(message: '没有可展示的设置项'),
              );
            } else {
              // 源站资料只读:左标签、右值,说明只在分组下方出现一次
              content = GroupedSection(
                header: '账号资料',
                footer: '资料只读，修改需在网页端进行。',
                children: [
                  for (final field in snap.data!.fields) _fieldRow(field),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 112),
              children: [
                ExpressivePageReveal(
                  active: true,
                  revision: (_seg, snap.connectionState),
                  child: content,
                ),
                // 检查更新与安装统计说明都在关于页里;有新版本时这里带红点
                GroupedSection(
                  header: '关于',
                  children: [
                    ListenableBuilder(
                      listenable: appUpdater,
                      builder: (context, _) => GroupedRow(
                        key: const ValueKey('settings-about'),
                        title: '关于 Chher',
                        value: AppInfo.version,
                        dot: appUpdater.hasUpdate,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.xs),
                          child: Image.asset(
                            appLogoAsset,
                            width: IconTile.size,
                            height: IconTile.size,
                          ),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AboutPage()),
                        ),
                      ),
                    ),
                  ],
                ),
                GroupedSection(
                  header: '诊断',
                  children: [
                    GroupedRow(
                      title: '运行日志',
                      icon: const IconTile(
                        icon: AppIcons.log,
                        tint: IconTints.teal,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LogPage()),
                      ),
                    ),
                    GroupedRow(
                      title: '图片缓存',
                      value: _cacheLabel,
                      icon: const IconTile(
                        icon: AppIcons.image,
                        tint: IconTints.teal,
                      ),
                      onTap: () => _clearCache(context),
                    ),
                  ],
                ),
                // 退出登录放在最底部,单独一组,先确认再清会话
                if (chhSession.loggedIn)
                  GroupedSection(
                    children: [
                      GroupedDestructiveRow(
                        label: '退出登录',
                        onTap: () => _logout(context),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    ],
  );

  Future<void> _clearCache(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除图片缓存？'),
        actions: [
          AppButton(
            label: '取消',
            variant: AppButtonVariant.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          AppButton(
            label: '清除',
            variant: AppButtonVariant.plain,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await imageDiskCache.clear();
    // 清除后重新统计,不显示过期的大小
    await _refreshCacheSize();
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出当前账号？'),
        actions: [
          AppButton(
            label: '取消',
            variant: AppButtonVariant.quiet,
            onPressed: () => Navigator.pop(context, false),
          ),
          AppButton(
            label: '退出',
            variant: AppButtonVariant.plain,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok == true) await chhSession.logout();
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
