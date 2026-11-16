/// 应用设置按外观、存储和关于分组。
library;

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';
import '../ui/press.dart';
import '../ui/sheet_scaffold.dart';
import '../design/icons.dart';
import '../design/shapes.dart';
import '../design/theme.dart';
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
        return Theme(
          data: buildAppTheme(targetBrightness, ctrl.style),
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
          title: '外观',
          card: false,
          child: ListenableBuilder(
            listenable: widget.appearanceController ?? appearance,
            builder: (context, _) => SettingsAppearance(
              controller: widget.appearanceController ?? appearance,
            ),
          ),
        ),
        _SettingsSection(
          key: const ValueKey('settings-storage'),
          title: '通用',
          child: Column(
            children: [
              _SettingsRow(
                title: '图片缓存',
                value: Text(
                  _cacheLabel,
                  style: SettingsTokens.valueLabel.copyWith(color: t.text3),
                ),
                leading: Icon(
                  SolarIconsBold.galleryMinimalistic,
                  size: 22,
                  color: t.text2,
                ),
                onTap: () => _clearCache(context),
              ),
              _SettingsRow(
                title: '运行日志',
                leading: Icon(AppIcons.logBold, size: 22, color: t.text2),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const LogPage())),
              ),
              ListenableBuilder(
                listenable: appUpdater,
                builder: (context, _) => _SettingsRow(
                  key: const ValueKey('settings-about'),
                  title: '关于 Chher',
                  value: appUpdater.hasUpdate
                      ? DecoratedBox(
                          key: const ValueKey('settings-update-badge'),
                          decoration: BoxDecoration(
                            color: t.accentFill,
                            borderRadius: BorderRadius.circular(AppRadii.full),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            child: Text(
                              '有新版本',
                              style: SettingsTokens.badgeLabel.copyWith(
                                color: t.accent,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          AppInfo.version,
                          style: SettingsTokens.valueLabel.copyWith(
                            color: t.text3,
                          ),
                        ),
                  leading: AppClip(
                    radius: SettingsTokens.logoRadius,
                    child: Image.asset(
                      appLogoAsset,
                      width: SettingsTokens.iconSize,
                      height: SettingsTokens.iconSize,
                    ),
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const AboutPage())),
                ),
              ),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: chhSession,
          builder: (context, _) => chhSession.loggedIn
              ? Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: t.surface,
                      shape: appShape(AppRadii.full),
                      shadows: SettingsTokens.cardShadow(t),
                    ),
                    child: AppClip(
                      radius: AppRadii.full,
                      child: PressHighlight(
                        key: const ValueKey('settings-logout'),
                        semanticLabel: '退出登录',
                        onTap: () => _logout(context),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: SettingsTokens.logoutHeight,
                          ),
                          child: Center(
                            child: Text(
                              '退出登录',
                              style: SettingsTokens.rowLabel.copyWith(
                                color: t.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
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
    final ok = await _confirm(context, title: '清除图片缓存？', action: '清除');
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
    final ok = await _confirm(context, title: '退出当前账号？', action: '退出');
    if (ok == true) await chhSession.logout();
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String action,
}) => showAppSheet<bool>(
  context,
  builder: (context) {
    final t = AppTokens.of(context);
    Widget button(String label, bool confirm) => PressScale(
      semanticLabel: label,
      onTap: () => Navigator.pop(context, confirm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: confirm ? t.red : t.fill,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SettingsTokens.confirmationButtonHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text(
                label,
                style: SettingsTokens.rowLabel.copyWith(
                  color: confirm ? SettingsTokens.strongForeground(t) : t.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.fill,
                  borderRadius: BorderRadius.circular(AppRadii.bar),
                ),
                child: const SizedBox(width: 36, height: 5),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: SettingsTokens.confirmationTitle.copyWith(color: t.text),
            ),
            const SizedBox(height: 26),
            button(action, true),
            const SizedBox(height: 8),
            button('取消', false),
          ],
        ),
      ),
    );
  },
);

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;
  final bool card;
  const _SettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.card = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Text(
              title,
              style: AppType.footnote.copyWith(
                color: t.text3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!card)
            child
          else
            DecoratedBox(
              decoration: ShapeDecoration(
                color: t.surface,
                shape: appShape(SettingsTokens.cardRadius),
                shadows: SettingsTokens.cardShadow(t),
              ),
              child: Padding(
                padding: const EdgeInsets.all(SettingsTokens.cardInset),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String title;
  final Widget leading;
  final Widget? value;
  final VoidCallback onTap;
  const _SettingsRow({
    super.key,
    required this.title,
    required this.leading,
    this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PressHighlight(
      semanticLabel: title,
      borderRadius: BorderRadius.circular(SettingsTokens.rowRadius),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: SettingsTokens.rowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                SizedBox.square(
                  dimension: SettingsTokens.iconSize,
                  child: Center(child: leading),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: SettingsTokens.rowLabel.copyWith(color: t.text),
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * .45,
                    ),
                    child: value!,
                  ),
                ],
                const SizedBox(width: 6),
                Icon(AppIcons.forward, size: 13, color: t.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
