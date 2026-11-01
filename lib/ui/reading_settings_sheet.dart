import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/reading_prefs.dart';
import '../design/reading.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import 'app_button.dart';
import 'picker.dart';
import 'segmented.dart';
import 'sheet_scaffold.dart';

Future<void> showReadingSettingsSheet(BuildContext context) {
  final controller = ReadingScope.maybeOf(context) ?? readingPrefs;
  return showAppSheet<void>(
    context,
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final prefs = controller.prefs;
        final metrics = ReadingMetrics.fromPrefs(prefs);
        final t = AppTokens.of(context);
        final fontLabel = const [
          '最小',
          '小',
          '标准',
          '大',
          '最大',
        ][prefs.fontSize.index];
        return SheetScaffold(
          title: '阅读设置',
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.screen),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '字号',
                        style: AppType.headline.copyWith(color: t.text),
                      ),
                    ),
                    Text(
                      '$fontLabel · ${metrics.bodySize.toInt()}',
                      style: AppType.footnote.copyWith(color: t.text2),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text('A', style: AppType.footnote.copyWith(color: t.text2)),
                    Expanded(
                      child: Slider(
                        value: prefs.fontSize.index.toDouble(),
                        max: 4,
                        divisions: 4,
                        label: fontLabel,
                        semanticFormatterCallback: (value) =>
                            const ['最小', '小', '标准', '大', '最大'][value.round()],
                        activeColor: t.accent,
                        inactiveColor: t.fill,
                        onChanged: (value) {
                          final size = ReadingFontSize.values[value.round()];
                          if (size == controller.prefs.fontSize) return;
                          HapticFeedback.selectionClick();
                          controller.set(
                            controller.prefs.copyWith(fontSize: size),
                          );
                        },
                      ),
                    ),
                    Text('A', style: AppType.title2.copyWith(color: t.text2)),
                  ],
                ),
                Text('行距', style: AppType.headline.copyWith(color: t.text)),
                const SizedBox(height: 8),
                AppSegmented<ReadingLineHeight>(
                  fallbackTitle: '行距',
                  options: const [
                    PickerOption(value: ReadingLineHeight.compact, label: '紧凑'),
                    PickerOption(
                      value: ReadingLineHeight.standard,
                      label: '标准',
                    ),
                    PickerOption(value: ReadingLineHeight.loose, label: '宽松'),
                  ],
                  value: prefs.lineHeight,
                  onChanged: (value) => controller.set(
                    controller.prefs.copyWith(lineHeight: value),
                  ),
                ),
                const SizedBox(height: 16),
                Text('布局', style: AppType.headline.copyWith(color: t.text)),
                const SizedBox(height: 8),
                AppSegmented<ReadingLayout>(
                  fallbackTitle: '布局',
                  options: const [
                    PickerOption(value: ReadingLayout.comfy, label: '舒适'),
                    PickerOption(value: ReadingLayout.compact, label: '紧凑'),
                  ],
                  value: prefs.layout,
                  onChanged: (value) =>
                      controller.set(controller.prefs.copyWith(layout: value)),
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: '恢复默认',
                  variant: AppButtonVariant.plain,
                  small: true,
                  onPressed: prefs.isDefault ? null : controller.reset,
                ),
                const SizedBox(height: 8),
                Text(
                  '帖子页和文章页通用 · 会叠加系统字体大小',
                  textAlign: TextAlign.center,
                  style: AppType.footnote.copyWith(color: t.text3),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    ),
  );
}
