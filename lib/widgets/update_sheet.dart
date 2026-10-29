/// 更新提示弹层与设置页“检查更新”入口
///
/// 弹层只是 [UpdateController] 的视图:关闭弹层不会中断下载,
/// 设置页的入口随时显示进度并能重新打开弹层。
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/app_button.dart';
import '../ui/feedback.dart';
import '../ui/sheet_scaffold.dart';
import '../update/update_client.dart';
import '../update/update_controller.dart';
import 'expressive_controls.dart';

String updateFailureText(UpdateFailure? failure) => switch (failure) {
  UpdateFailure.notConfigured => '更新服务未配置',
  UpdateFailure.untrusted => '更新信息校验失败',
  UpdateFailure.busy => '更新服务繁忙，请稍后再试',
  UpdateFailure.notFound => '没有找到这个版本',
  UpdateFailure.integrity => '安装包校验失败，请重新下载',
  UpdateFailure.signer => '安装包签名与当前应用不一致',
  UpdateFailure.install => '安装没有完成，可以重试',
  UpdateFailure.storage => '无法保存安装包，请检查存储空间',
  _ => '无法连接更新服务，请稍后重试',
};

String _megabytes(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

/// 冷启动时调用:刚更新完提示一次;有新版本且未被忽略时弹出更新提示
Future<void> runLaunchUpdateCheck(
  BuildContext context, [
  UpdateController? controller,
]) async {
  final updater = controller ?? appUpdater;
  final updated = await updater.takeJustUpdated();
  if (updated != null && context.mounted) {
    AppToast.show(context, '已更新到 $updated', icon: AppIcons.success);
  }
  if (await updater.checkOnLaunch() && context.mounted) {
    await UpdateSheet.show(context, updater);
  }
}

class UpdateSheet extends StatefulWidget {
  final UpdateController controller;
  const UpdateSheet({super.key, required this.controller});

  static Future<void> show(
    BuildContext context,
    UpdateController controller,
  ) async {
    await showAppSheet<void>(
      context,
      builder: (_) => UpdateSheet(controller: controller),
    );
    controller.dismiss();
  }

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> with WidgetsBindingObserver {
  UpdateController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 用户从“允许安装未知应用”设置页回来后继续安装
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _c.resumeAfterPermission();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _c,
    builder: (context, _) {
      final release = _c.release;
      if (release == null) return const SizedBox.shrink();
      return SheetScaffold(
        title: '发现新版本',
        contextLine: '${release.versionName}，${_megabytes(release.size)} MB',
        body: _notes(context, release.notes),
        footer: _footer(context),
      );
    },
  );

  Widget _notes(BuildContext context, String notes) {
    final t = AppTokens.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .4,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.screen,
          4,
          AppSpace.screen,
          8,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            notes.isEmpty ? '修复问题并改进体验' : notes,
            style: AppType.subhead.copyWith(color: t.text),
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final t = AppTokens.of(context);
    final phase = _c.phase;
    final Widget content = switch (phase) {
      UpdatePhase.downloading => _downloading(t),
      UpdatePhase.verifying || UpdatePhase.installing => Center(
        child: AppButton(label: '正在安装', state: AppButtonState.busy),
      ),
      UpdatePhase.needsPermission => _permission(t),
      _ => _choices(t),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        12,
        AppSpace.screen,
        12,
      ),
      // 状态之间只淡入淡出,不跳动
      child: ExpressivePageReveal(
        active: true,
        revision: phase == UpdatePhase.failed ? UpdatePhase.available : phase,
        child: content,
      ),
    );
  }

  Widget _choices(AppTokens t) {
    final failed = _c.phase == UpdatePhase.failed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              updateFailureText(_c.failure),
              style: AppType.footnote.copyWith(color: t.red),
            ),
          ),
        Row(
          children: [
            if (!_c.force)
              AppButton(
                key: const ValueKey('update-ignore'),
                label: '忽略此版本',
                variant: AppButtonVariant.quiet,
                onPressed: () async {
                  await _c.ignoreCurrent();
                  if (mounted) Navigator.of(context).maybePop();
                },
              ),
            const Spacer(),
            if (!_c.force)
              AppButton(
                label: '以后再说',
                variant: AppButtonVariant.plain,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            const SizedBox(width: 8),
            AppButton(
              key: const ValueKey('update-start'),
              label: failed ? '重试' : '立即更新',
              small: true,
              onPressed: failed ? _c.retry : _c.download,
            ),
          ],
        ),
      ],
    );
  }

  Widget _downloading(AppTokens t) {
    final total = _c.total == 0 ? 1 : _c.total;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '下载进度',
          value: '${_c.received * 100 ~/ total}%',
          child: LinearProgressIndicator(
            value: _c.received / total,
            minHeight: 6,
            color: t.accent,
            backgroundColor: t.fill,
            borderRadius: BorderRadius.circular(AppRadii.bar),
          ),
        ),
        Row(
          children: [
            Text(
              '${_megabytes(_c.received)} / ${_megabytes(_c.total)} MB',
              style: AppType.footnote.copyWith(color: t.text3),
            ),
            const Spacer(),
            AppButton(
              label: '取消下载',
              variant: AppButtonVariant.quiet,
              onPressed: _c.cancelDownload,
            ),
          ],
        ),
      ],
    );
  }

  Widget _permission(AppTokens t) => Row(
    children: [
      Expanded(
        child: Text(
          '需要允许 Chher 安装应用',
          style: AppType.subhead.copyWith(color: t.text2),
        ),
      ),
      AppButton(label: '去开启', small: true, onPressed: _c.openInstallPermission),
    ],
  );
}

/// 关于页版本号右侧的“检查更新”:只是一段蓝色可点文字,随状态变成进度或“有新版本”
class UpdateCheckLink extends StatelessWidget {
  final UpdateController? controller;
  const UpdateCheckLink({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller ?? appUpdater;
    final t = AppTokens.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final label = _label(c);
        return Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            key: const ValueKey('update-check-link'),
            behavior: HitTestBehavior.opaque,
            onTap: c.busy ? null : () => _open(context, c),
            // 文字小,上下各留出点按余量
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Text(
                label,
                style: AppType.subhead.copyWith(
                  color: t.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _label(UpdateController c) => switch (c.phase) {
    UpdatePhase.checking => '检查中…',
    UpdatePhase.downloading =>
      '下载中 ${c.total == 0 ? 0 : c.received * 100 ~/ c.total}%',
    UpdatePhase.verifying || UpdatePhase.installing => '正在安装',
    _ when c.newerVersionKnown => '有新版本',
    _ => '检查更新',
  };

  /// 本次已拿到版本信息就直接弹出更新提示;否则先检查(上次记下的新版本也要重新取详情)
  Future<void> _open(BuildContext context, UpdateController c) async {
    if (c.release != null && c.phase != UpdatePhase.upToDate) {
      await UpdateSheet.show(context, c);
      return;
    }
    if (c.busy) return;
    await c.checkManually();
    if (!context.mounted) return;
    switch (c.phase) {
      case UpdatePhase.available:
        await UpdateSheet.show(context, c);
      case UpdatePhase.upToDate:
        AppToast.show(context, '已是最新版本', icon: AppIcons.success);
        c.dismiss();
      case UpdatePhase.failed:
        AppToast.show(context, updateFailureText(c.failure));
        c.dismiss();
      default:
        break;
    }
  }
}
