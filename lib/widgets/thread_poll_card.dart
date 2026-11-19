import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';
import '../design/loading_tokens.dart';
import '../design/motion.dart';
import '../design/poll_tokens.dart';
import '../design/tokens.dart';
import '../models/poll.dart';
import '../ui/press.dart';
import 'chhers_loader.dart';

class ThreadPollCard extends StatefulWidget {
  final ThreadPoll poll;
  final Future<PollVoteResult> Function(Set<String>)? onSubmit;
  final VoidCallback? onVoters;
  const ThreadPollCard({
    super.key,
    required this.poll,
    this.onSubmit,
    this.onVoters,
  });
  @override
  State<ThreadPollCard> createState() => _ThreadPollCardState();
}

class _ThreadPollCardState extends State<ThreadPollCard>
    with TickerProviderStateMixin {
  late ThreadPoll _poll = widget.poll;
  final _selected = <String>{};
  bool _busy = false, _success = false, _expanded = false;
  String? _error;
  late final AnimationController _bars, _extra;
  @override
  void initState() {
    super.initState();
    _bars = AnimationController(vsync: this, value: 1);
    _extra = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant ThreadPollCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poll != widget.poll) _poll = widget.poll;
  }

  @override
  void dispose() {
    _bars.dispose();
    _extra.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _selected.isEmpty || widget.onSubmit == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.onSubmit!(Set.of(_selected));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _success = result.success;
        if (result.success && result.poll != null) _poll = result.poll!;
        if (!result.success) _error = result.message ?? '没有投上，请稍后再试';
      });
      if (result.success) {
        _bars.value = 0;
        AppMotion.settle(
          _bars,
          target: 1,
          motion: AppMotion.reveal,
          reduced: MediaQuery.disableAnimationsOf(context),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '没有投上，请稍后再试';
        });
      }
    }
  }

  String? get _hint {
    if (_error != null) return _error;
    if (_success) return '✓ 已投票';
    if (_poll.closed) return _poll.hasResults ? '投票已关闭' : '投票已关闭，结果未公开';
    if (_poll.ended) return '投票已经结束';
    if (_poll.alreadyVoted) return '✓ 你已经投过票';
    if (_poll.multiple == true) {
      return '最多选 ${_poll.maxChoices ?? ''} 项，已选 ${_selected.length}';
    }
    return _selected.isEmpty ? '选一项后投票' : null;
  }

  String? get _deadline {
    if (_poll.resultsAfterVote && !_poll.hasResults) return '投票后可以看到结果';
    final raw = _poll.deadline;
    if (raw == null || _poll.ended) return null;
    final day = RegExp(r'(\d+)\s*天').firstMatch(raw)?.group(1);
    final hour = RegExp(r'(\d+)\s*小时').firstMatch(raw)?.group(1);
    if (day != null || hour != null) {
      return '还剩 ${[if (day != null) '$day 天', if (hour != null) '$hour 小时'].join(' ')}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final canVote = _poll.canVote && !_success;
    final type = _poll.multiple == null
        ? null
        : _poll.multiple!
        ? (_poll.maxChoices == null ? '多选' : '多选，最多 ${_poll.maxChoices} 项')
        : '单选';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(PollTokens.radius),
        boxShadow: t.shadowE1,
      ),
      child: Padding(
        padding: PollTokens.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: PollTokens.iconBox,
                  height: PollTokens.iconBox,
                  decoration: BoxDecoration(
                    color: t.accentFill,
                    borderRadius: BorderRadius.circular(PollTokens.wrapInset),
                  ),
                  child: Icon(
                    SolarIconsOutline.checklistMinimalistic,
                    size: PollTokens.icon,
                    color: t.accent,
                  ),
                ),
                const SizedBox(width: PollTokens.titleGap),
                Text(
                  '投票',
                  style: PollTokens.text(
                    PollTokens.titleSize,
                    t.text,
                    FontWeight.w700,
                  ),
                ),
                const SizedBox(width: PollTokens.titleGap),
                if (type != null)
                  Expanded(
                    child: Text(
                      type,
                      style: PollTokens.text(
                        PollTokens.metaSize,
                        t.text2,
                        FontWeight.w600,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (_poll.participantCount != null)
                  Text(
                    '${_poll.participantCount} 人参与',
                    style: PollTokens.text(PollTokens.metaSize, t.text3),
                  ),
              ],
            ),
            if (_deadline != null)
              Padding(
                padding: const EdgeInsets.only(
                  left: PollTokens.iconBox + PollTokens.titleGap,
                ),
                child: Text(
                  _deadline!,
                  style: PollTokens.text(PollTokens.metaSize, t.text3),
                ),
              ),
            const SizedBox(height: PollTokens.optionsGap),
            for (
              var i = 0;
              i < _poll.options.length.clamp(0, PollTokens.collapsedCount);
              i++
            )
              _option(i, canVote),
            if (_expanded)
              AnimatedBuilder(
                animation: _extra,
                child: Column(
                  children: [
                    for (
                      var i = PollTokens.collapsedCount;
                      i < _poll.options.length;
                      i++
                    )
                      _option(i, canVote),
                  ],
                ),
                builder: (_, child) => ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: _extra.value,
                    child: child,
                  ),
                ),
              ),
            if (!_expanded && _poll.options.length > PollTokens.collapsedCount)
              PressScale(
                onTap: () {
                  setState(() => _expanded = true);
                  AppMotion.settle(
                    _extra,
                    target: 1,
                    motion: AppMotion.reveal,
                    reduced: MediaQuery.disableAnimationsOf(context),
                  );
                },
                child: SizedBox(
                  height: PollTokens.buttonTouch,
                  child: Center(
                    child: Text(
                      '展开其余 ${_poll.options.length - PollTokens.collapsedCount} 项 ⌄',
                      style: PollTokens.text(PollTokens.linkSize, t.text2),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (_poll.closed || _poll.ended) ...[
                        Icon(
                          _poll.closed
                              ? SolarIconsOutline.lockKeyhole
                              : SolarIconsOutline.clockCircle,
                          size: PollTokens.metaSize,
                          color: t.text2,
                        ),
                        const SizedBox(width: PollTokens.gap),
                      ],
                      Expanded(
                        child: Text(
                          _hint ?? '',
                          style: PollTokens.text(
                            PollTokens.metaSize,
                            _error != null
                                ? Theme.of(context).colorScheme.error
                                : _success
                                ? t.accent
                                : t.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (canVote) _button(t),
                if (_poll.participantsUrl != null && widget.onVoters != null)
                  PressScale(
                    onTap: widget.onVoters,
                    child: Padding(
                      padding: const EdgeInsets.all(PollTokens.wrapInset),
                      child: Text(
                        '参与人 ›',
                        style: PollTokens.text(
                          PollTokens.linkSize,
                          t.text2,
                          FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(AppTokens t) {
    final enabled = !_busy && _selected.isNotEmpty && widget.onSubmit != null;
    return PressScale(
      onTap: enabled ? _submit : null,
      semanticLabel: _poll.multiple == true
          ? '投票，已选 ${_selected.length} 项，最多 ${_poll.maxChoices ?? ''} 项'
          : '投票',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: (PollTokens.buttonTouch - PollTokens.optionHeight) / 2,
        ),
        child: Container(
          height: PollTokens.optionHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: PollTokens.buttonInset,
          ),
          decoration: BoxDecoration(
            color: enabled ? t.accent : t.fill,
            gradient: enabled && t.style == AppearanceStyle.cinnabar
                ? t.btnGradient
                : null,
            borderRadius: BorderRadius.circular(PollTokens.optionRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy) ...[
                const ChhersSpinner(size: LoadingTokens.input),
                const SizedBox(width: PollTokens.gap),
              ],
              Text(
                _busy
                    ? '投票中'
                    : _error != null
                    ? '重试'
                    : '投票',
                style: PollTokens.text(
                  PollTokens.percentSize,
                  enabled ? t.onAccent : t.text3,
                  FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(int index, bool canVote) {
    final option = _poll.options[index];
    final t = AppTokens.of(context);
    final selected = option.id != null && _selected.contains(option.id);
    final full =
        _poll.multiple == true &&
        _poll.maxChoices != null &&
        _selected.length >= _poll.maxChoices!;
    final disabled = canVote && !selected && full;
    final maxVotes = _poll.options.fold<int>(
      -1,
      (a, b) => (b.votes ?? -1) > a ? b.votes! : a,
    );
    final top =
        option.votes != null &&
        index == _poll.options.indexWhere((o) => o.votes == maxVotes);
    Color faded(Color c) => disabled
        ? Color.alphaBlend(
            t.surface.withValues(alpha: 1 - PollTokens.disabledAlpha),
            c,
          )
        : c;
    final label =
        '${option.text}${option.percentage == null ? '' : '，${option.percentage!.round()}%'}${option.votes == null ? '' : '，${option.votes} 票'}${canVote ? '，${_poll.multiple == true ? '多选' : '单选'}，${selected ? '已选中' : '未选中'}' : ''}${option.mine ? '，我的选择' : ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: PollTokens.gap),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final style = PollTokens.text(PollTokens.optionSize, faded(t.text));
          final resultText = option.percentage == null
              ? ''
              : '${option.percentage!.round()}%  ${option.votes ?? ''} 票';
          final resultPainter = TextPainter(
            text: TextSpan(
              text: resultText,
              style: PollTokens.text(PollTokens.percentSize, t.text),
            ),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final available =
              (constraints.maxWidth -
                      PollTokens.optionInset * 2 -
                      (canVote ? PollTokens.mark + PollTokens.markInset : 0) -
                      resultPainter.width -
                      (resultText.isNotEmpty ? PollTokens.gap : 0))
                  .clamp(1.0, double.infinity);
          final painter = TextPainter(
            text: TextSpan(
              text: '${option.text}${option.mine ? ' ✓ 我的选择' : ''}',
              style: style,
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: available);
          final wrap = painter.computeLineMetrics().length > 1;
          final radius = BorderRadius.circular(
            wrap ? PollTokens.wrapRadius : PollTokens.optionRadius,
          );
          return Semantics(
            label: label,
            selected: canVote ? selected : null,
            child: ExcludeSemantics(
              child: PressScale(
                scale: PollTokens.pressScale,
                onTap: canVote && !_busy && !disabled && option.id != null
                    ? () => setState(() {
                        if (selected) {
                          _selected.remove(option.id);
                        } else {
                          if (_poll.multiple != true) _selected.clear();
                          _selected.add(option.id!);
                        }
                        _error = null;
                      })
                    : null,
                child: ClipRRect(
                  borderRadius: radius,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: selected
                              ? Color.alphaBlend(
                                  t.accent.withValues(
                                    alpha: PollTokens.selectedAlpha,
                                  ),
                                  t.surface,
                                )
                              : t.fill3,
                        ),
                      ),
                      if (option.percentage != null)
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _bars,
                            builder: (_, _) => Transform.scale(
                              alignment: Alignment.centerLeft,
                              scaleX:
                                  _bars.value *
                                  (option.percentage! / 100).clamp(
                                    PollTokens.minimumBar,
                                    1,
                                  ),
                              scaleY: 1,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: PollTokens.bar(
                                    t,
                                    Theme.of(context).brightness ==
                                        Brightness.dark,
                                    top,
                                  ),
                                  borderRadius: radius,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: PollTokens.optionHeight,
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            canVote
                                ? PollTokens.markInset
                                : PollTokens.optionInset,
                            wrap ? PollTokens.wrapInset : 0,
                            PollTokens.optionInset,
                            wrap ? PollTokens.wrapInset : 0,
                          ),
                          child: Row(
                            children: [
                              if (canVote) ...[
                                AnimatedContainer(
                                  duration:
                                      MediaQuery.disableAnimationsOf(context)
                                      ? Duration.zero
                                      : AppMotion.fade,
                                  width: PollTokens.mark,
                                  height: PollTokens.mark,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? t.accent
                                        : t.surface.withValues(alpha: 0),
                                    border: Border.all(
                                      color: selected
                                          ? t.accent.withValues(alpha: 0)
                                          : faded(t.text3),
                                      width: PollTokens.markStroke,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      _poll.multiple == true
                                          ? PollTokens.markRadius
                                          : PollTokens.mark,
                                    ),
                                  ),
                                  child: selected
                                      ? Icon(
                                          Icons.check,
                                          size: PollTokens.metaSize,
                                          color: Radix.whiteA12,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: PollTokens.markInset),
                              ],
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    text: option.text,
                                    style: style,
                                    children: [
                                      if (option.mine)
                                        TextSpan(
                                          text: ' ✓ 我的选择',
                                          style: PollTokens.text(
                                            PollTokens.mineSize,
                                            t.accent,
                                            FontWeight.w600,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (option.percentage != null) ...[
                                const SizedBox(width: PollTokens.gap),
                                Text(
                                  '${option.percentage!.round()}%',
                                  style: PollTokens.text(
                                    PollTokens.percentSize,
                                    faded(top ? t.accent : t.text),
                                    FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: PollTokens.gap),
                                if (option.votes != null)
                                  Text(
                                    '${option.votes} 票',
                                    style: PollTokens.text(
                                      PollTokens.votesSize,
                                      faded(t.text3),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
