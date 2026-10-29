/// 构建标识
///
/// 每个分发包都要能自证身份:之前几个包的 versionName 与 versionCode 完全相同,
/// 装没装上只能靠猜界面,排查时浪费了一整轮。
library;

abstract final class AppInfo {
  /// 由 --dart-define=app_version=... 注入,与 pubspec 的 version 保持一致
  static const String version = String.fromEnvironment(
    'app_version',
    defaultValue: 'dev',
  );

  /// 由 --dart-define=build_stamp=... 注入的构建时间
  static const String buildStamp = String.fromEnvironment(
    'build_stamp',
    defaultValue: '本地调试',
  );

  static String get label => '$version / $buildStamp';
}
