import 'package:flutter/material.dart';

import '../design/reading.dart';
import '../design/thread_page_tokens.dart';
import '../design/thread_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/balanced_title.dart';

/// The article route owns this state from its first frame through the handoff.
class ThreadLandingChrome {
  final offset = ValueNotifier<double>(0);
  final collapsed = ValueNotifier<bool>(false);
  final progress = ValueNotifier<double>(0);
  final progressVisible = ValueNotifier<bool>(false);
  String? title;
  Uri? sourceUrl;

  void dispose() {
    offset.dispose();
    collapsed.dispose();
    progress.dispose();
    progressVisible.dispose();
  }
}

TextStyle threadTitleStyle(AppTokens tokens) => TextStyle(
  fontSize: ThreadPageTokens.titleSize,
  height: ThreadPageTokens.titleHeight,
  fontWeight: FontWeight.w700,
  color: tokens.text,
  letterSpacing: ThreadPageTokens.titleTracking,
);

/// Use the real text metrics for reserved metadata without inventing values.
class ThreadHeadingSpace extends StatelessWidget {
  final TextStyle style;
  const ThreadHeadingSpace({super.key, required this.style});

  @override
  Widget build(BuildContext context) => Visibility(
    visible: false,
    maintainState: true,
    maintainAnimation: true,
    maintainSize: true,
    child: Text(' ', style: style),
  );
}

TextStyle threadEyebrowStyle(AppTokens tokens) => TextStyle(
  fontSize: ThreadMetrics.metaSize,
  color: tokens.accent,
  fontWeight: FontWeight.w600,
);

class ThreadLandingSkeleton extends StatelessWidget {
  final String title;
  final bool bars;
  final bool showTitle;

  const ThreadLandingSkeleton({
    super.key,
    required this.title,
    required this.bars,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final metrics = ReadingMetrics.of(context);
    final scaler = metrics.textScaler(MediaQuery.textScalerOf(context));
    final titleStyle = threadTitleStyle(tokens);
    Widget line(double width, double lineHeight) => SizedBox(
      height: lineHeight,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.fill,
              borderRadius: BorderRadius.circular(
                ThreadPageTokens.skeletonRadius,
              ),
            ),
            child: const SizedBox(height: ThreadPageTokens.skeletonLine),
          ),
        ),
      ),
    );
    Widget titleSlot() {
      if (title.trim().isEmpty) {
        return Visibility(
          visible: bars,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: Column(
            children: [
              for (final width in ThreadPageTokens.skeletonTitleWidths)
                line(
                  width,
                  scaler.scale(titleStyle.fontSize!) * titleStyle.height!,
                ),
            ],
          ),
        );
      }
      return Visibility(
        visible: showTitle,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: BalancedTitle(title, style: titleStyle),
      );
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          metrics.gutter,
          ThreadPageTokens.headingTop,
          metrics.gutter,
          metrics.postVPad,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ThreadHeadingSpace(style: threadEyebrowStyle(tokens)),
            const SizedBox(height: ThreadPageTokens.eyebrowGap),
            titleSlot(),
            const SizedBox(height: ThreadPageTokens.statsGap),
            const ThreadHeadingSpace(style: AppType.footnote),
            SizedBox(height: ThreadPageTokens.headingBottom + metrics.postVPad),
            Visibility(
              visible: bars,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.surface2,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox.square(
                            dimension: metrics.openingAvatar,
                          ),
                        ),
                        const SizedBox(width: ThreadTokens.authorAvatarGap),
                        Expanded(
                          child: Column(
                            children: [
                              for (final width
                                  in ThreadPageTokens.skeletonAuthorWidths)
                                line(width, scaler.scale(AppType.sizeFootnote)),
                            ],
                          ),
                        ),
                        const SizedBox(width: ThreadTokens.authorMoreTarget),
                      ],
                    ),
                    const SizedBox(height: ThreadTokens.bodyTop),
                    for (final width in ThreadPageTokens.skeletonBodyWidths)
                      line(
                        width,
                        scaler.scale(metrics.bodySize) *
                            metrics.threadBodyHeight,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
