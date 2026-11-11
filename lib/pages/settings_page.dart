/// 应用设置按外观、存储和关于分组。
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';
import '../ui/segmented.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/picker.dart';
import '../di.dart';
import '../data/image_disk_cache.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/expressive_controls.dart';
import '../ui/feedback.dart';
import '../ui/grouped.dart';
import '../update/update_controller.dart';
import '../core/app_info.dart';
import '../core/appearance.dart';
import 'about_page.dart';
import 'log_page.dart';

class SettingsPage extends StatelessWidget {
  final AppearanceController? appearanceController;
  const SettingsPage({super.key, this.appearanceController});
  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '设置',
    surface: AppSurface.grouped,
    body: SettingsBody(appearanceController: appearanceController),
  );
}

class SettingsBody extends StatefulWidget {
  final AppearanceController? appearanceController;
  const SettingsBody({super.key, this.appearanceController});
  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  // 缓存大小异步统计,算完前行上显示占位,不阻塞设置页出现
  String _cacheLabel = '计算中';

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  @override
  void dispose() {
    // 朱砂红上线引导:用户查看过设置页后消费红点(离开页面时底栏、
    // 设置行、风格选项的红点全部消失并持久化,后续安装更新不再出现)。
    // 放在 dispose 而非 initState:让设置页内"朱砂红"选项上的红点
    // 至少可见一次,引导才成立。
    (widget.appearanceController ?? appearance).markStyleDotSeen();
    super.dispose();
  }

  Future<void> _refreshCacheSize() async {
    String label;
    try {
      label = _formatBytes(await imageDiskCache.totalBytes());
    } catch (_) {
      // 统计失败时给中性值,不让占位一直挂着
      label = '—';
    }
    if (mounted) setState(() => _cacheLabel = label);
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 112),
    children: [
      ListenableBuilder(
        listenable: widget.appearanceController ?? appearance,
        builder: (context, _) {
          final controller = widget.appearanceController ?? appearance;
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 7),
                  child: Text(
                    '外观',
                    style: AppType.footnote.copyWith(
                      color: AppTokens.of(context).text3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.screen,
                  ),
                  child: AppSegmented<AppearanceMode>(
                    fallbackTitle: '外观',
                    options: [
                      for (final mode in AppearanceMode.values)
                        PickerOption(value: mode, label: mode.label),
                    ],
                    value: controller.mode,
                    onChanged: controller.set,
                  ),
                ),
                // 界面风格:薄雾白(1.0.7 纸面)与朱砂红(漆面),与明暗正交
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 20, 32, 7),
                  child: Text(
                    '界面风格',
                    style: AppType.footnote.copyWith(
                      color: AppTokens.of(context).text3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.screen,
                  ),
                  child: AppSegmented<AppearanceStyle>(
                    fallbackTitle: '界面风格',
                    options: [
                      for (final style in AppearanceStyle.values)
                        PickerOption(
                          value: style,
                          label: style.label,
                          // 朱砂红上线引导:未进过设置页时新主题带红点
                          dot:
                              style == AppearanceStyle.cinnabar &&
                              !controller.styleDotSeen,
                        ),
                    ],
                    value: controller.style,
                    onChanged: controller.setStyle,
                  ),
                ),
              ],
            ),
          );
        },
      ),
      GroupedSection(
        header: '存储',
        children: [
          GroupedRow(
            title: '图片缓存',
            value: _cacheLabel,
            icon: const IconTile(icon: AppIcons.image, tint: IconTints.teal),
            onTap: () => _clearCache(context),
          ),
        ],
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
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AboutPage())),
            ),
          ),
          GroupedRow(
            title: '运行日志',
            icon: const IconTile(icon: AppIcons.log, tint: IconTints.teal),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LogPage())),
          ),
        ],
      ),
      // 退出登录放在最底部,单独一组,先确认再清会话
      ListenableBuilder(
        listenable: chhSession,
        builder: (context, _) => chhSession.loggedIn
            ? GroupedSection(
                children: [
                  GroupedDestructiveRow(
                    label: '退出登录',
                    onTap: () => _logout(context),
                  ),
                ],
              )
            : const SizedBox.shrink(),
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
    try {
      await imageDiskCache.clear();
    } catch (_) {
      if (context.mounted) AppToast.show(context, '清除失败，请稍后重试');
    } finally {
      // 无论清除是否成功都重新统计,不显示过期的大小
      await _refreshCacheSize();
    }
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
            variant: AppButtonVariant.destructive,
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
