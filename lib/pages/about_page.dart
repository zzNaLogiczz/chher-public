/// 关于:应用图标、版本号与检查更新、介绍、反馈
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_info.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/chrome_button.dart';
import '../ui/feedback.dart';
import '../ui/grouped.dart';
import '../widgets/link_opener.dart';
import '../widgets/update_sheet.dart';

/// 应用图标,与启动图标同源(tool/launcher_icon.py 生成)
const appLogoAsset = 'assets/brand/chher-logo.png';

const feedbackEmail = 'zznalogic@gmail.com';

/// 反馈邮件:标题带上版本号,省得来回确认
Uri feedbackMailUri() => Uri(
  scheme: 'mailto',
  path: feedbackEmail,
  query: 'subject=${Uri.encodeComponent('Chher 反馈（${AppInfo.version}）')}',
);

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const _logoSize = 88.0;

  /// 交给邮件应用;手机上没有可用的邮件应用时复制地址
  Future<void> _mail(BuildContext context) async {
    bool ok;
    try {
      ok = await externalLauncher(feedbackMailUri());
    } catch (_) {
      ok = false;
    }
    if (ok || !context.mounted) return;
    await Clipboard.setData(const ClipboardData(text: feedbackEmail));
    if (context.mounted) AppToast.show(context, '已复制邮箱地址');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final body = AppType.body.copyWith(color: t.text, height: 1.75);
    return Scaffold(
      backgroundColor: t.grouped,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.only(top: top + 64, bottom: 48),
            children: [
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    boxShadow: t.shadowE1,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    child: Image.asset(
                      appLogoAsset,
                      width: _logoSize,
                      height: _logoSize,
                      semanticLabel: 'Chher 图标',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Chher',
                textAlign: TextAlign.center,
                style: AppType.title2.copyWith(color: t.text),
              ),
              // 版本号右侧就是检查更新:有新版本时文字变成"有新版本"
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '版本 ${AppInfo.version}',
                    key: const ValueKey('about-version'),
                    style: AppType.subhead.copyWith(color: t.text2),
                  ),
                  const SizedBox(width: 6),
                  const UpdateCheckLink(),
                ],
              ),
              const SizedBox(height: 28),
              GroupedSection(
                header: '介绍',
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.rowInset,
                      14,
                      AppSpace.rowInset,
                      16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chher 是 Chiphell 论坛的第三方 Android 客户端，'
                          '为在手机上阅读和参与讨论而做，由坛友自制。',
                          style: body,
                        ),
                        const SizedBox(height: 10),
                        Text('本项目为公益项目，不以盈利为目的。', style: body),
                      ],
                    ),
                  ),
                ],
              ),
              GroupedSection(
                header: '反馈',
                footer: '遇到 bug 或有功能需求，欢迎来信。',
                children: [
                  GroupedRow(
                    key: const ValueKey('about-feedback'),
                    title: '发送邮件',
                    value: feedbackEmail,
                    valueColor: t.accent,
                    onTap: () => _mail(context),
                  ),
                ],
              ),
              Padding(
                // 与分组说明同一缩进
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.groupInset + AppSpace.rowInset,
                  4,
                  AppSpace.groupInset + AppSpace.rowInset,
                  0,
                ),
                child: Text(
                  '检查更新时会发送一个随机生成的安装标识，用于统计安装量和分批推送更新；'
                  '不关联论坛账号，也不读取设备信息。',
                  style: AppType.footnote.copyWith(color: t.text3, height: 1.6),
                ),
              ),
            ],
          ),
          Positioned(
            top: top + 4,
            left: 10,
            child: ChromeButton(
              icon: AppIcons.back,
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}
