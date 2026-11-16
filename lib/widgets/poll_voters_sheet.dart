import 'package:flutter/material.dart';
import '../data/poll_repository.dart';
import '../design/poll_tokens.dart';
import '../design/tokens.dart';
import '../models/models.dart';
import '../models/poll.dart';
import '../pages/user_drawer.dart';
import '../ui/press.dart';
import '../ui/sheet_scaffold.dart';
import 'avatar_image.dart';
import 'state_view.dart';

Future<void> showPollVotersSheet(
  BuildContext context, {
  required ThreadPoll poll,
  required PollRepository repository,
}) => showAppSheet<void>(
  context,
  expandable: true,
  builder: (_) => PollVotersSheet(poll: poll, repository: repository),
);

class PollVotersSheet extends StatefulWidget {
  final ThreadPoll poll;
  final PollRepository repository;
  const PollVotersSheet({
    super.key,
    required this.poll,
    required this.repository,
  });
  @override
  State<PollVotersSheet> createState() => _PollVotersSheetState();
}

class _PollVotersSheetState extends State<PollVotersSheet> {
  PollVotersPage? _data;
  final _voters = <PollVoter>[];
  String? _option;
  bool _loading = false, _exhausted = false;
  Object? _error;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool append = false}) async {
    if (append && _loading) return;
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
      if (!append) {
        _voters.clear();
        _exhausted = false;
      }
    });
    try {
      final page = await widget.repository.participants(
        widget.poll,
        optionId: _option,
        page: append ? _data!.page.current + 1 : 1,
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        final previousPage = _data?.page.current ?? 0;
        final fresh = page.voters
            .where((voter) => !_voters.any((known) => known.uid == voter.uid))
            .toList();
        _exhausted =
            append && (page.page.current <= previousPage || fresh.isEmpty);
        if (!_exhausted) {
          _data = page;
          _option = page.selectedOptionId;
          _voters.addAll(fresh);
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SheetScaffold(
      title: '参与人',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_data != null)
            SizedBox(
              height: PollTokens.buttonTouch,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: PollTokens.optionInset,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: _data!.options.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: PollTokens.gap),
                itemBuilder: (context, index) {
                  final option = _data!.options[index];
                  final selected = option.id == _option;
                  return Center(
                    child: Semantics(
                      selected: selected,
                      child: PressScale(
                        onTap: selected
                            ? null
                            : () {
                                setState(() => _option = option.id);
                                _load();
                              },
                        child: Container(
                          height: PollTokens.chipHeight,
                          padding: const EdgeInsets.symmetric(
                            horizontal: PollTokens.optionInset,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? t.accentFill : t.fill3,
                            borderRadius: BorderRadius.circular(
                              PollTokens.chipRadius,
                            ),
                          ),
                          child: Text(
                            option.text,
                            style: PollTokens.text(
                              PollTokens.chipSize,
                              selected ? t.accent : t.text2,
                              FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          Flexible(
            child: _voters.isEmpty
                ? _state()
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _voters.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _voters.length) {
                        return _error != null
                            ? _state()
                            : _loading
                            ? SizedBox(
                                height: PollTokens.voterHeight,
                                child: StateView.loading(),
                              )
                            : !_exhausted && _data!.page.hasNext
                            ? PressScale(
                                onTap: () => _load(append: true),
                                child: SizedBox(
                                  height: PollTokens.voterHeight,
                                  child: Center(
                                    child: Text(
                                      '下一页',
                                      style: PollTokens.text(
                                        PollTokens.linkSize,
                                        t.text2,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink();
                      }
                      final voter = _voters[index];
                      return PressHighlight(
                        onTap: () =>
                            showUserDrawer(context, voter.uid.toString()),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: PollTokens.optionInset,
                          ),
                          child: SizedBox(
                            height: PollTokens.voterHeight,
                            child: Row(
                              children: [
                                AvatarImage(
                                  url: voter.avatarUrl,
                                  name: voter.name,
                                  size: PollTokens.iconBox,
                                ),
                                const SizedBox(width: PollTokens.optionsGap),
                                Expanded(
                                  child: Text(
                                    voter.name,
                                    style: PollTokens.text(
                                      PollTokens.voterSize,
                                      t.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _state() {
    final error = _error;
    if (_loading) {
      return SizedBox(
        height: PollTokens.voterHeight,
        child: StateView.loading(),
      );
    }
    if (error is PageMessage) {
      return StateView(icon: Icons.lock_outline, message: error.text);
    }
    if (error != null) {
      return StateView.error(
        error,
        onRetry: () => _load(append: _voters.isNotEmpty),
      );
    }
    return StateView.empty(message: '还没有人投这一项');
  }
}
