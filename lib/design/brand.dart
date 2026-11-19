import 'dart:ui';

const appDisplayName = 'Chhers';

/// 应用内品牌图标与启动图标同源。
const appLogoAsset = 'assets/brand/chhers-logo.png';

/// R2b-Chh-ers-light.svg 的两行标志，使用原始坐标，不含图标底板。
Path buildChhersMarkPath() => Path()
  ..moveTo(23.05, 16.05)
  ..arcToPoint(
    const Offset(23.05, -3.05),
    radius: const Radius.circular(13.5),
    largeArc: true,
  )
  ..moveTo(34.45, -7)
  ..lineTo(34.45, 20)
  ..moveTo(34.45, 7.2)
  ..arcToPoint(const Offset(48.85, 7.2), radius: const Radius.circular(7.2))
  ..moveTo(48.85, 7.2)
  ..lineTo(48.85, 20)
  ..moveTo(62.05, -7)
  ..lineTo(62.05, 20)
  ..moveTo(62.05, 7.2)
  ..arcToPoint(const Offset(76.45, 7.2), radius: const Radius.circular(7.2))
  ..moveTo(76.45, 7.2)
  ..lineTo(76.45, 20)
  ..moveTo(21.71, 48.83)
  ..arcToPoint(
    const Offset(24.05, 42.4),
    radius: const Radius.circular(10),
    largeArc: true,
  )
  ..moveTo(4.05, 42.4)
  ..lineTo(24.05, 42.4)
  ..moveTo(34.45, 32.4)
  ..lineTo(34.45, 52.4)
  ..moveTo(34.45, 40.68)
  ..arcToPoint(const Offset(42.73, 32.4), radius: const Radius.circular(8.28))
  ..moveTo(42.73, 32.4)
  ..lineTo(44.83, 32.4)
  ..moveTo(66.53, 34.6)
  ..cubicTo(65.53, 33.1, 63.63, 32.4, 61.43, 32.4)
  ..cubicTo(57.83, 32.4, 55.23, 34.5, 55.23, 37.4)
  ..cubicTo(55.23, 40.8, 58.63, 41.6, 61.63, 42.3)
  ..cubicTo(64.83, 43, 68.03, 43.9, 68.03, 47.3)
  ..cubicTo(68.03, 50.4, 65.23, 52.4, 61.43, 52.4)
  ..cubicTo(58.83, 52.4, 56.43, 51.4, 55.03, 49.6);
