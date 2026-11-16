/// Session-aware boundary; voting only starts from the card's submit action.
library;

import 'package:flutter/material.dart';
import '../di.dart';
import '../models/poll.dart';
import 'thread_poll_card.dart';
import 'poll_voters_sheet.dart';

class ConnectedThreadPoll extends StatefulWidget {
  final ThreadPoll poll;
  final ValueChanged<ThreadPoll>? onUpdated;
  const ConnectedThreadPoll({super.key, required this.poll, this.onUpdated});

  @override
  State<ConnectedThreadPoll> createState() => _ConnectedThreadPollState();
}

class _ConnectedThreadPollState extends State<ConnectedThreadPoll> {
  late ThreadPoll _poll = widget.poll;
  int _read = 0;
  late int _revision = chhSession.identityRevision;

  @override
  void initState() {
    super.initState();
    chhSession.addListener(_sessionChanged);
    _restoreChoices();
  }

  void _sessionChanged() {
    if (_revision == chhSession.identityRevision) return;
    _revision = chhSession.identityRevision;
    _restoreChoices();
  }

  Future<void> _restoreChoices() async {
    final read = ++_read;
    await pollStorageReady;
    if (!mounted || read != _read) return;
    final poll = await pollRepo.withMyChoices(widget.poll);
    if (mounted && read == _read) setState(() => _poll = poll);
  }

  @override
  void didUpdateWidget(covariant ConnectedThreadPoll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.poll, widget.poll)) _restoreChoices();
  }

  @override
  void dispose() {
    _read++;
    chhSession.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ThreadPollCard(
    key: ValueKey(_revision),
    poll: _poll,
    onSubmit: (ids) async {
      if (!chhSession.loggedIn) {
        await Navigator.of(context).pushNamed('/login');
        // Returning from login never submits a vote automatically.
        return PollVoteResult(
          success: false,
          message: chhSession.loggedIn ? '已登录，请再次点投票' : '请先登录',
        );
      }
      final result = await pollRepo.vote(_poll, ids);
      if (mounted && result.success && result.poll != null) {
        _poll = result.poll!;
        widget.onUpdated?.call(_poll);
      }
      return result;
    },
    onVoters: _poll.participantsUrl == null
        ? null
        : () => showPollVotersSheet(context, poll: _poll, repository: pollRepo),
  );
}
