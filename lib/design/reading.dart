import 'package:flutter/widgets.dart';

import '../core/reading_prefs.dart';

/// Only reading content consumes these tokens; navigation keeps its own scale.
class ReadingMetrics {
  static const double commentMetaGap = 8;

  /// 至少留出回复向上扩展的触区，避免换行后覆盖时间。
  static const double commentMetaRunGap = 12;

  /// Android 数字时间（默认 Roboto）旁的中文回复（Noto Sans CJK）光学校正。
  /// 共用基线后，13px 字号在 DPR 4、0.9/1/2 倍下墨迹仍低 4/4/8px；
  /// 上提 0.08em 并随 TextScaler 缩放，不绑定设备物理像素。
  /// 仅用于数字日期/时间；中文相对时间、其他平台不套用此字体组合的校正。
  static const double commentReplyOpticalLiftEm = .08;

  final ReadingPrefs prefs;
  const ReadingMetrics.fromPrefs(this.prefs);

  double get bodySize =>
      const [15.0, 16.0, 17.0, 18.0, 20.0][prefs.fontSize.index];
  double get bodyHeight => const [1.55, 1.7, 1.85][prefs.lineHeight.index];
  double get commentSize => bodySize - 1;
  double get commentHeight => bodyHeight - .1;
  bool get _compact => prefs.layout == ReadingLayout.compact;
  double get gutter => _compact ? 16 : 20;
  double get postVPad => _compact ? 8 : 12;
  double get avatar => _compact ? 28 : 32;
  double get avatarNested => _compact ? 22 : 24;
  double get openingAvatar => _compact ? 32 : 36;
  double get paragraphGap => _compact ? 6 : 10;
  double get titleSize => _compact ? 22 : 24;
  double get imageGap => _compact ? 8 : 12;
  double get sectionBand => _compact ? 6 : 8;

  TextScaler textScaler(TextScaler system) =>
      system.clamp(maxScaleFactor: 26 / bodySize);

  static ReadingMetrics of(BuildContext context) => ReadingMetrics.fromPrefs(
    ReadingScope.maybeOf(context)?.prefs ?? const ReadingPrefs(),
  );
}

class ReadingScope extends InheritedNotifier<ReadingPrefsController> {
  const ReadingScope({
    super.key,
    required ReadingPrefsController controller,
    required super.child,
  }) : super(notifier: controller);

  static ReadingPrefsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ReadingScope>()?.notifier;
}
