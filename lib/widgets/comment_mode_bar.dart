/// 评论区的查看方式切换:帖子与门户文章共用同一个控件和同一套切换规则。
///
/// 切换时控件停在原处,只有它下方的评论内容更新;需要读取网络的方式
/// (只看楼主)先在控件上选中并显示等待,内容到达后再替换,失败退回原方式。
library;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/picker.dart';
import '../ui/segmented.dart';

/// 三种查看方式互斥:按回复归组的评论、站点原始顺序、只看作者本人
enum CommentViewMode { threaded, floors, author }

/// 全宽三段分段:评论 / 原楼层 / 只看楼主(文章为"只看作者")。
/// 宽度固定占满一行,不随计数文字长短换行;放不下时降级为选择按钮。
class CommentModeBar extends StatelessWidget {
  final CommentViewMode mode;
  final ValueChanged<CommentViewMode> onChanged;
  final String authorLabel;

  /// 认不出作者时不提供第三段,不给一个必然为空的选项
  final bool showAuthor;

  const CommentModeBar({
    super.key,
    required this.mode,
    required this.onChanged,
    this.authorLabel = '只看楼主',
    this.showAuthor = true,
  });

  @override
  Widget build(BuildContext context) => AppSegmented<CommentViewMode>(
    fallbackTitle: '查看方式',
    options: [
      const PickerOption(value: CommentViewMode.threaded, label: '评论'),
      const PickerOption(value: CommentViewMode.floors, label: '原楼层'),
      if (showAuthor)
        PickerOption(value: CommentViewMode.author, label: authorLabel),
    ],
    value: mode,
    onChanged: onChanged,
  );
}

/// 计数位置上的等待指示:切换方式读取网络期间代替旧计数
class CommentModeBusy extends StatelessWidget {
  const CommentModeBusy({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: t.text3,
              ),
            ),
          ),
        ],
      ),
      semanticsLabel: '正在切换',
      style: AppType.footnote,
    );
  }
}
