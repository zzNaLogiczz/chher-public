/// 应用设置按外观、存储和关于分组。
library;

import 'package:flutter/material.dart';
import '../ui/app_button.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/shapes.dart';
import '../design/theme.dart';
import '../ui/grouped.dart';
import '../widgets/account_widgets.dart';
import '../widgets/settings_appearance.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import '../data/image_disk_cache.dart';
import '../widgets/large_title_scaffold.dart';
import '../ui/feedback.dart';
import '../update/update_controller.dart';
import '../core/app_info.dart';
import '../core/appearance.dart';
import 'about_page.dart';
import 'log_page.dart';

class SettingsPage extends StatelessWidget {
  final AppearanceController? appearanceController;
  const SettingsPage({super.key, this.appearanceController});

  @override
  Widget build(BuildContext context) {
    final ctrl = appearanceController ?? appearance;
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final outerBrightness = Theme.of(context).brightness;
        final targetBrightness = switch (ctrl.mode) {
          AppearanceMode.light => Brightness.light,
          AppearanceMode.dark => Brightness.dark,
          AppearanceMode.system => outerBrightness,
        };
        final disableAnimations = MediaQuery.disableAnimationsOf(context);
        return AnimatedTheme(
          data: buildAppTheme(targetBrightness, ctrl.style),
          duration: disableAnimations
              ? Duration.zero
              : AppMotion.revealDuration,
          curve: AppMotion.revealCurve,
          child: LargeTitleScaffold(
            title: '设置',
            surface: AppSurface.grouped,
            body: SettingsBody(appearanceController: appearanceController),
          ),
        );
      },
    );
  }
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
    // 朱砂上线引导:用户查看过设置页后消费红点(离开页面时底栏、
    // 设置行、风格选项的红点全部消失并持久化,后续安装更新不再出现)。
    // 放在 dispose 而非 initState:让设置页内"朱砂"选项上的红点
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
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.groupInset,
        0,
        AppSpace.groupInset,
        64,
      ),
      children: [
        _SettingsSection(
          key: const ValueKey('settings-appearance'),
          title: '外观与风格',
          child: ListenableBuilder(
            listenable: widget.appearanceController ?? appearance,
            builder: (context, _) => SettingsAppearance(
              controller: widget.appearanceController ?? appearance,
            ),
          ),
        ),
        _SettingsSection(
          key: const ValueKey('settings-storage'),
          title: '存储与诊断',
          child: Column(
            children: [
              GroupedRow(
                title: '图片缓存',
                value: _cacheLabel,
                leading: const AccountToolWell(icon: AppIcons.imageBold),
                onTap: () => _clearCache(context),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpace.rowInset + IconTile.size + 12,
                ),
                child: Divider(
                  height: AppSpace.hairline,
                  thickness: AppSpace.hairline,
                  color: t.separator.withValues(alpha: .42),
                ),
              ),
              GroupedRow(
                title: '运行日志',
                leading: const AccountToolWell(icon: AppIcons.logBold),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogPage()),
                ),
              ),
            ],
          ),
        ),
        _SettingsSection(
          key: const ValueKey('settings-about-section'),
          title: '关于',
          child: ListenableBuilder(
            listenable: appUpdater,
            builder: (context, _) => GroupedRow(
              key: const ValueKey('settings-about'),
              title: '关于 Chher',
              value: AppInfo.version,
              dot: appUpdater.hasUpdate,
              leading: AppClip(
                radius: AppRadii.xs,
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
        ),
        ListenableBuilder(
          listenable: chhSession,
          builder: (context, _) => chhSession.loggedIn
              ? Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: t.surface,
                      shape: appShape(AppRadii.md),
                    ),
                    child: AppClip(
                      radius: AppRadii.md,
                      child: GroupedDestructiveRow(
                        key: const ValueKey('settings-logout'),
                        label: '退出登录',
                        onTap: () => _logout(context),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

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

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _SettingsSection({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.rowInset,
              0,
              AppSpace.rowInset,
              7,
            ),
            child: Text(
              title,
              style: AppType.footnote.copyWith(
                color: t.text3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DecoratedBox(
            decoration: ShapeDecoration(
              color: t.surface,
              shape: appShape(AppRadii.md),
            ),
            child: AppClip(radius: AppRadii.md, child: child),
          ),
        ],
      ),
    );
  }
}
