import 'models.dart' show PageInfo;

class PollOption {
  final String text;
  final String? id;
  final int? votes;
  final double? percentage;
  final bool mine;
  const PollOption({
    required this.text,
    this.id,
    this.votes,
    this.percentage,
    this.mine = false,
  });
  PollOption withMine(bool value) => PollOption(
    text: text,
    id: id,
    votes: votes,
    percentage: percentage,
    mine: value,
  );
}

class ThreadPoll {
  final int tid;
  final bool? multiple;
  final int? maxChoices;
  final int? participantCount;
  final String? deadline;
  final bool resultsAfterVote, alreadyVoted, closed, ended;
  final Uri? action, participantsUrl;
  final List<PollOption> options;
  const ThreadPoll({
    required this.tid,
    this.multiple,
    this.maxChoices,
    this.participantCount,
    this.deadline,
    this.resultsAfterVote = false,
    this.alreadyVoted = false,
    this.closed = false,
    this.ended = false,
    this.action,
    this.participantsUrl,
    required this.options,
  });
  bool get canVote =>
      !alreadyVoted &&
      !closed &&
      !ended &&
      action != null &&
      options.any((o) => o.id != null);
  bool get hasResults => options.any((o) => o.votes != null);
  ThreadPoll withOptions(List<PollOption> value) => ThreadPoll(
    tid: tid,
    multiple: multiple,
    maxChoices: maxChoices,
    participantCount: participantCount,
    deadline: deadline,
    resultsAfterVote: resultsAfterVote,
    alreadyVoted: alreadyVoted,
    closed: closed,
    ended: ended,
    action: action,
    participantsUrl: participantsUrl,
    options: value,
  );
}

class PollVoterOption {
  final String id, text;
  const PollVoterOption({required this.id, required this.text});
}

class PollVoter {
  final int uid;
  final String name;
  final String? avatarUrl;
  const PollVoter({required this.uid, required this.name, this.avatarUrl});
}

class PollVotersPage {
  final List<PollVoterOption> options;
  final List<PollVoter> voters;
  final String? selectedOptionId;
  final PageInfo page;
  const PollVotersPage({
    required this.options,
    required this.voters,
    this.selectedOptionId,
    required this.page,
  });
}

class PollVoteResult {
  final bool success;
  final ThreadPoll? poll;
  final String? message;
  const PollVoteResult({required this.success, this.poll, this.message});
}
