import 'package:flutter/widgets.dart';

import '../design/display_text.dart';
import '../design/typography.dart';

/// Reflows a short final line without changing the number of title lines.
class BalancedTitle extends StatefulWidget {
  final String title;
  final TextStyle style;
  final int? maxLines;

  /// The resting width for a title that shares a moving cover.
  final double? measurementWidth;

  const BalancedTitle(
    this.title, {
    super.key,
    required this.style,
    this.maxLines,
    this.measurementWidth,
  });

  @override
  State<BalancedTitle> createState() => _BalancedTitleState();
}

class _BalancedTitleState extends State<BalancedTitle> {
  Object? _measurement;
  double? _balancedWidth;

  @override
  Widget build(BuildContext context) {
    final title = normalizeDisplayText(widget.title);
    final defaults = DefaultTextStyle.of(context);
    var style = defaults.style.merge(widget.style);
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);
    final heightBehavior =
        defaults.textHeightBehavior ??
        DefaultTextHeightBehavior.maybeOf(context);
    final maxLines = widget.maxLines ?? defaults.maxLines;
    final label = Text(
      title,
      style: widget.style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = widget.measurementWidth ?? constraints.maxWidth;
        if (!available.isFinite || available <= 0 || title.trim().isEmpty) {
          return label;
        }
        final measurement = (
          title,
          available,
          style,
          scaler,
          maxLines,
          direction,
          locale,
          heightBehavior,
        );
        if (_measurement != measurement) {
          _measurement = measurement;
          final painter = TextPainter(
            text: TextSpan(text: title, style: style),
            textDirection: direction,
            textScaler: scaler,
            locale: locale,
            maxLines: maxLines,
            textHeightBehavior: heightBehavior,
          )..layout(maxWidth: available);
          _balancedWidth = _findWidth(title, painter, available);
          painter.dispose();
        }
        final width = _balancedWidth ?? widget.measurementWidth;
        if (width == null) return label;
        return Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox(width: width, child: label),
        );
      },
    );
  }

  double? _findWidth(String title, TextPainter painter, double available) {
    final lines = painter.computeLineMetrics().length;
    if (lines < 2 || painter.didExceedMaxLines) return null;
    final lastCharacter = TextPosition(offset: title.trimRight().length - 1);
    final last = painter.getLineBoundary(lastCharacter);
    final tail = title.substring(last.start, last.end).trim();
    if (tail.characters.length >= AppType.titleOrphanMinLength) return null;

    var low = 0.0;
    var high = available;
    while (high - low > AppType.titleBalancePrecision) {
      final middle = (low + high) / 2;
      painter.layout(maxWidth: middle);
      if (painter.didExceedMaxLines ||
          painter.computeLineMetrics().length > lines) {
        low = middle;
      } else {
        high = middle;
      }
    }
    painter.layout(maxWidth: high);
    return painter.getLineBoundary(lastCharacter).start < last.start
        ? high
        : null;
  }
}
