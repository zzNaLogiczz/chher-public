import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../models/models.dart';
import 'press.dart';
import 'sheet_scaffold.dart';

const noticeViews = NoticeView.values;
const noticeViewLabels = ['全部', '我的帖子', '互动', '系统', '应用'];

List<({String label, String? value})> noticeTypes(int view) =>
    switch (noticeViews[view]) {
      NoticeView.mypost => [
        (label: '全部类型', value: null),
        (label: '回复', value: 'post'),
        (label: '评分', value: 'rate'),
        (label: '点评', value: 'pcomment'),
        (label: '提到我', value: 'at'),
        (label: '活动', value: 'activity'),
        (label: '悬赏', value: 'reward'),
        (label: '商品', value: 'goods'),
      ],
      NoticeView.interactive => [
        (label: '全部类型', value: null),
        (label: '打招呼', value: 'poke'),
        (label: '好友', value: 'friend'),
        (label: '留言', value: 'wall'),
        (label: '评论', value: 'comment'),
        (label: '互动', value: 'click'),
        (label: '分享', value: 'sharenotice'),
      ],
      _ => [(label: '全部类型', value: null)],
    };

class NoticeFilter extends StatelessWidget {
  const NoticeFilter({
    super.key,
    required this.view,
    required this.type,
    required this.onChanged,
  });
  final int view;
  final String? type;
  final void Function(int, String?) onChanged;
  String get label =>
      noticeTypes(
        view,
      ).where((e) => e.value == type && type != null).firstOrNull?.label ??
      noticeViewLabels[view];
  @override
  Widget build(BuildContext context) => MessageFilterLabel(
    label: label,
    onTap: () => showAppSheet<void>(
      context,
      builder: (_) =>
          _NoticeFilterPanel(view: view, type: type, onChanged: onChanged),
    ),
  );
}

class _NoticeFilterPanel extends StatefulWidget {
  const _NoticeFilterPanel({
    required this.view,
    required this.type,
    required this.onChanged,
  });
  final int view;
  final String? type;
  final void Function(int, String?) onChanged;
  @override
  State<_NoticeFilterPanel> createState() => _NoticeFilterPanelState();
}

class _NoticeFilterPanelState extends State<_NoticeFilterPanel> {
  late int _view = widget.view;
  late String? _type = widget.type;
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    Widget option(String text, bool selected, VoidCallback tap) => PressScale(
      onTap: tap,
      semanticLabel: text,
      child: Semantics(
        selected: selected,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppSizes.singleLineHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? t.accentFill : t.fill,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              text,
              style: AppType.subhead.copyWith(
                color: selected ? t.accent : t.text,
              ),
            ),
          ),
        ),
      ),
    );
    return SheetScaffold(
      title: '提醒类型',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < noticeViews.length; i++)
                  option(noticeViewLabels[i], i == _view, () {
                    setState(() {
                      _view = i;
                      _type = null;
                    });
                    widget.onChanged(i, null);
                  }),
              ],
            ),
            const SizedBox(height: 16),
            // Only the newly exposed subtype section grows; the five types stay put.
            AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : AppMotion.revealDuration,
              curve: AppMotion.revealCurve,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final type in noticeTypes(_view))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: option(type.label, type.value == _type, () {
                        widget.onChanged(_view, type.value);
                        Navigator.of(context).pop();
                      }),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageFilterLabel extends StatefulWidget {
  const MessageFilterLabel({
    super.key,
    required this.label,
    required this.onTap,
  });
  final String label;
  final VoidCallback onTap;
  @override
  State<MessageFilterLabel> createState() => _MessageFilterLabelState();
}

class _MessageFilterLabelState extends State<MessageFilterLabel>
    with SingleTickerProviderStateMixin {
  late final _swap = AnimationController.unbounded(vsync: this, value: 1);
  String? _previous;
  @override
  void didUpdateWidget(MessageFilterLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label) {
      _previous = oldWidget.label;
      _swap.value = 0;
      AppMotion.settle(
        _swap,
        target: 1,
        motion: AppMotion.select,
        reduced: MediaQuery.disableAnimationsOf(context),
      );
    }
  }

  @override
  void dispose() {
    _swap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PressScale(
      onTap: widget.onTap,
      semanticLabel: widget.label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRect(
              child: AnimatedBuilder(
                animation: _swap,
                builder: (_, _) {
                  final p = _swap.value.clamp(0.0, 1.0);
                  final style = AppType.footnote.copyWith(
                    fontWeight: FontWeight.w600,
                  );
                  return Stack(
                    children: [
                      if (p < 1 && _previous != null)
                        Positioned.fill(
                          child: Transform.translate(
                            offset: Offset(0, -20 * p),
                            child: Text(
                              _previous!,
                              style: style.copyWith(
                                color: t.text2.withValues(alpha: 1 - p),
                              ),
                            ),
                          ),
                        ),
                      Transform.translate(
                        offset: Offset(0, 20 * (1 - p)),
                        child: Text(
                          widget.label,
                          style: style.copyWith(
                            color: t.text2.withValues(alpha: p),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Icon(AppIcons.down, size: 14, color: t.text2),
          ],
        ),
      ),
    );
  }
}

class PmFilterLabel extends StatelessWidget {
  const PmFilterLabel({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => MessageFilterLabel(
      label: value == 0 ? '私人消息' : '公共消息',
      onTap: () async {
        final box = anchor.findRenderObject()! as RenderBox;
        final rect = box.localToGlobal(Offset.zero) & box.size;
        final reduced = MediaQuery.disableAnimationsOf(context);
        final selected = await showGeneralDialog<int>(
          context: context,
          barrierDismissible: true,
          barrierLabel: '关闭',
          barrierColor: AppTokens.of(context).scrim.withValues(alpha: 0),
          transitionDuration: reduced
              ? Duration.zero
              : AppMotion.curveOf(AppMotion.pop).duration,
          transitionBuilder: (_, _, _, child) => child,
          pageBuilder: (context, animation, _) {
            final t = AppTokens.of(context);
            return Stack(
              children: [
                Positioned(
                  left: rect.left,
                  top: rect.bottom,
                  child: ScaleTransition(
                    alignment: Alignment.topLeft,
                    scale: Tween(begin: .9, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: AppMotion.curveOf(AppMotion.pop),
                      ),
                    ),
                    child: Material(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (i, label) in ['私人消息', '公共消息'].indexed)
                              PressHighlight(
                                onTap: () => Navigator.of(context).pop(i),
                                semanticLabel: label,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                  child: Text(
                                    label,
                                    style: AppType.subhead.copyWith(
                                      color: i == value ? t.accent : t.text,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
        if (selected != null) onChanged(selected);
      },
    ),
  );
}
