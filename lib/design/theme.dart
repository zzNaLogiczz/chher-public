/// ThemeData 构建:把设计令牌接到 Material 组件上
///
/// TextTheme 槽位只映射 typography.dart 的字号角色,防止组件偷偷引入新字号。
library;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'
    show
        CupertinoPageTransitionsBuilder,
        CupertinoThemeData,
        CupertinoTextThemeData;

import 'tokens.dart';
import 'typography.dart';
import '../widgets/expressive_controls.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final t = brightness == Brightness.dark ? AppTokens.dark : AppTokens.light;

  // 中文走系统字:iOS 为 PingFang SC,Android 为思源 / Noto Sans CJK SC。
  // 不打包任何 CJK 字体(单字重十几 MB)。
  final textTheme = _buildTextTheme(t);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    cupertinoOverrideTheme: CupertinoThemeData(
      primaryColor: t.accent,
      scaffoldBackgroundColor: t.bg,
      barBackgroundColor: t.surface,
      textTheme: CupertinoTextThemeData(
        primaryColor: t.accent,
        textStyle: TextStyle(fontSize: AppType.sizeBody, color: t.text),
        navActionTextStyle: TextStyle(
          fontSize: AppType.sizeBody,
          color: t.accent,
        ),
        tabLabelTextStyle: TextStyle(
          fontSize: AppType.sizeFootnote,
          color: t.text2,
        ),
      ),
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(AppIcons.back, size: 22),
      closeButtonIconBuilder: (_) => const Icon(AppIcons.close, size: 22),
    ),
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.separator,
    extensions: [t],
    colorScheme: _colorScheme(t, brightness),
    textTheme: textTheme,
    dividerTheme: const DividerThemeData(
      thickness: AppSpace.hairline,
      space: AppSpace.hairline,
    ),
    appBarTheme: _appBarTheme(t, textTheme),
    cardTheme: _cardTheme(t),
    listTileTheme: ListTileThemeData(
      textColor: t.text,
      iconColor: t.text3,
      minVerticalPadding: 0,
    ),
    inputDecorationTheme: _inputTheme(t),
    textButtonTheme: _textButtonTheme(t),
    outlinedButtonTheme: _outlinedButtonTheme(t),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearMinHeight: 2,
    ),
    snackBarTheme: _snackBarTheme(t),
    bottomSheetTheme: _bottomSheetTheme(t),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accentFill,
        foregroundColor: t.accent,
        minimumSize: const Size(44, 46),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        textStyle: const TextStyle(
          fontSize: AppType.sizeBody,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.all(10),
        foregroundColor: t.text2,
        iconSize: 22,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _ReadingPageTransitions(),
        TargetPlatform.iOS: _ReadingPageTransitions(),
        TargetPlatform.macOS: _ReadingPageTransitions(),
      },
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: t.fill.withValues(alpha: .65),
    hoverColor: t.fill.withValues(alpha: .45),
  );
}

ColorScheme _colorScheme(AppTokens t, Brightness brightness) {
  return ColorScheme(
    brightness: brightness,
    primary: t.accent,
    onPrimary: t.onAccent,
    primaryContainer: t.accentFill,
    onPrimaryContainer: t.accent,
    secondary: t.text2,
    onSecondary: t.surface,
    secondaryContainer: t.fill,
    onSecondaryContainer: t.text,
    tertiary: t.accent,
    onTertiary: t.surface,
    tertiaryContainer: t.accentFill,
    onTertiaryContainer: t.accent,
    error: t.red,
    onError: t.onAccent,
    surface: t.bg,
    onSurface: t.text,
    onSurfaceVariant: t.text2,
    surfaceContainerLowest: t.surface,
    surfaceContainerLow: t.bg,
    surfaceContainer: t.fill,
    surfaceContainerHigh: t.fill2,
    surfaceContainerHighest: t.separator,
    outline: t.separator,
    outlineVariant: t.separator,
    shadow: Radix.slate12Light,
    scrim: t.scrim,
    inverseSurface: t.text,
    onInverseSurface: t.bg,
    inversePrimary: t.accentFill,
    surfaceTint: t.accent,
  );
}

AppBarTheme _appBarTheme(AppTokens t, TextTheme textTheme) {
  return AppBarTheme(
    backgroundColor: t.bg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    toolbarHeight: 58,
    iconTheme: IconThemeData(color: t.text2, size: 21),
    actionsIconTheme: IconThemeData(color: t.text2, size: 20),
    titleTextStyle: textTheme.titleLarge,
    titleSpacing: 8,
  );
}

/// Standard cards use a subtle boundary; editorial elevation is applied locally.
CardThemeData _cardTheme(AppTokens t) {
  return CardThemeData(
    color: t.surface,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.md),
      side: BorderSide(color: t.separator, width: AppSpace.hairline),
    ),
  );
}

InputDecorationTheme _inputTheme(AppTokens t) {
  final radius = BorderRadius.circular(AppRadii.sm);
  return InputDecorationTheme(
    filled: true,
    fillColor: t.fill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    hintStyle: TextStyle(fontSize: AppType.sizeFootnote, color: t.text3),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: t.accent, width: AppSpace.hairline),
    ),
  );
}

TextButtonThemeData _textButtonTheme(AppTokens t) {
  return TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: t.accent,
      textStyle: const TextStyle(
        fontSize: AppType.sizeFootnote,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      minimumSize: const Size(44, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
    ),
  );
}

OutlinedButtonThemeData _outlinedButtonTheme(AppTokens t) {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: t.accent,
      side: BorderSide(color: t.separator, width: AppSpace.hairline),
      textStyle: const TextStyle(
        fontSize: AppType.sizeFootnote,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      minimumSize: const Size(44, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
    ),
  );
}

SnackBarThemeData _snackBarTheme(AppTokens t) {
  return SnackBarThemeData(
    backgroundColor: t.text,
    contentTextStyle: TextStyle(fontSize: AppType.sizeFootnote, color: t.bg),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
  );
}

BottomSheetThemeData _bottomSheetTheme(AppTokens t) {
  return BottomSheetThemeData(
    backgroundColor: t.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
  );
}

/// 字号角色映射:display/headline -> largeTitle,title -> title2/headline,
/// body -> body/callout/footnote,label -> subhead/footnote/caption
TextTheme _buildTextTheme(AppTokens t) {
  TextStyle c(TextStyle s, [Color? color, FontWeight? w]) =>
      s.copyWith(color: color ?? t.text, fontWeight: w);

  return TextTheme(
    displayLarge: c(AppType.largeTitle),
    displayMedium: c(AppType.largeTitle),
    displaySmall: c(AppType.largeTitle),
    headlineLarge: c(AppType.largeTitle),
    headlineMedium: c(AppType.largeTitle),
    headlineSmall: c(AppType.largeTitle),
    titleLarge: c(AppType.title2),
    titleMedium: c(AppType.headline),
    titleSmall: c(AppType.footnote, null, FontWeight.w600),
    bodyLarge: c(AppType.body),
    bodyMedium: c(AppType.callout),
    bodySmall: c(AppType.footnote, t.text2),
    labelLarge: c(AppType.subhead, null, FontWeight.w600),
    labelMedium: c(AppType.footnote, t.text2, FontWeight.w500),
    labelSmall: c(AppType.caption, t.text3),
  );
}

class _ReadingPageTransitions extends PageTransitionsBuilder {
  const _ReadingPageTransitions();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return const CupertinoPageTransitionsBuilder().buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
