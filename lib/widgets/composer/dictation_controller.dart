import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/composer_tokens.dart';
import '../../design/voice_tokens.dart';
import '../../voice/hands_free_volume.dart';
import '../../voice/speech_engine.dart';
import 'voice_goo_motion.dart';

enum DictationPhase {
  idle,
  press,
  hold,
  locked,
  finalizing,
  review,
  canceling,
  errorPermission,
  errorNetwork,
  errorUnavailable,
  errorSilent,
  errorBusy,
}

/// Read-only input for the voice bar and transcript overlay.
/// Pointer positions are global logical pixels. The text range uses UTF-16
/// offsets, as does the editor.
typedef DictationFrame = ({
  DictationPhase phase,
  Offset? pointer,
  double pull,
  bool detached,
  bool retracting,
  bool holdBar,
  double volume,
  int seconds,
  bool hitLimit,
  SpeechText text,
  TextRange insertedRange,
});

typedef DictationVisualFrame = ({
  double volume,
  Offset? dropCenter,
  double? flyElapsed,
  double? cancelElapsed,
});

class DictationController extends ValueNotifier<DictationFrame> {
  static const _limit = Duration(seconds: VoiceTokens.secondsPerMinute);
  static const _silence = Duration(seconds: 4);

  final TextEditingController editor;
  final SpeechEngine Function() createEngine;
  final SpeechClock _clock;
  final visual = ValueNotifier<DictationVisualFrame>((
    volume: 0,
    dropCenter: null,
    flyElapsed: null,
    cancelElapsed: null,
  ));

  _DictationSession? _session;
  Offset? _origin;
  Duration? _pressedAt;
  Offset? _pointer;
  double _pull = 0;
  bool _detached = false;
  bool _wantsHold = false;
  bool _retracting = false;
  bool _holdCancelBar = false;
  bool _flyCancel = false;
  int _presentations = 0;
  bool _disposed = false;

  Timer? _holdTimer;
  Timer? _statusTimer;
  Timer? _cancelTimer;
  Timer? _tickTimer;
  Timer? _silenceTimer;
  Timer? _textSilenceTimer;
  Duration? _readyAt;
  int _seconds = 0;
  bool _hitLimit = false;
  double _volume = 0;
  DictationPhase _phase = DictationPhase.idle;
  SpeechText _text = const SpeechText(finalized: '', interim: '');
  TextRange _inserted = TextRange.empty;
  bool _hasWritten = false;
  bool _writing = false;
  late TextEditingValue _lastEdit;

  DictationController({
    required this.editor,
    required this.createEngine,
    SpeechClock? clock,
  }) : _clock = clock ?? SystemSpeechClock(),
       super((
         phase: DictationPhase.idle,
         pointer: null,
         pull: 0,
         detached: false,
         retracting: false,
         holdBar: false,
         volume: 0,
         seconds: 0,
         hitLimit: false,
         text: const SpeechText(finalized: '', interim: ''),
         insertedRange: TextRange.empty,
       )) {
    _lastEdit = editor.value;
    editor.addListener(_editorChanged);
  }

  bool get active => _session != null;
  bool get editorLocked => active || _flyCancel;
  bool get listening => active && _phase != DictationPhase.finalizing;
  Duration get listeningElapsed {
    final readyAt = _readyAt;
    return listening && readyAt != null
        ? _clock.elapsed - readyAt
        : Duration.zero;
  }

  bool get barExpanded => listening || _holdCancelBar;
  bool get canUndo =>
      _phase != DictationPhase.canceling &&
      _hasWritten &&
      !_inserted.isCollapsed;

  late final editingGuard = TextInputFormatter.withFunction((before, after) {
    if (_writing ||
        !_flyCancel ||
        (before.text == after.text && before.composing == after.composing)) {
      return after;
    }
    return before;
  });

  void start({Offset? pointer}) {
    if (active) return;
    _cancelTimer?.cancel();
    _holdCancelBar = false;
    _clearGesture();
    editor.clearComposing();
    final selection = editor.selection;
    final start = selection.isValid ? selection.start : editor.text.length;
    final end = selection.isValid ? selection.end : start;
    _inserted = TextRange(
      start: start.clamp(0, editor.text.length),
      end: end.clamp(0, editor.text.length),
    );
    _hasWritten = false;
    _text = const SpeechText(finalized: '', interim: '');
    _seconds = 0;
    _hitLimit = false;
    _volume = 0;
    _origin = _pointer = pointer;
    _pressedAt = pointer == null ? null : _clock.elapsed;
    _wantsHold = false;

    final session = _session = _DictationSession(createEngine());
    final engine = session.engine;
    session.subscriptions.addAll([
      engine.text.listen((text) {
        if (_session != session) return;
        _text = text;
        final recognized = text.combined;
        if (recognized.isNotEmpty && recognized != session.lastRecognized) {
          session.lastRecognized = recognized;
          _armTextSilence();
        }
        if (_hasWritten || recognized.isNotEmpty) {
          _replace(recognized);
        }
        _publish();
      }, onDone: () => _streamClosed(session)),
      engine.volume.listen((volume) {
        if (_session != session || !listening) return;
        _volume = volume;
        if (session.handsFreeVolume?.hasVoice(_clock.elapsed, volume) ??
            false) {
          _armSilence();
        }
        _publish();
      }),
      engine.errors.listen(
        (error) => session.error = error,
        onDone: () => _streamClosed(session),
      ),
    ]);
    _setPhase(DictationPhase.press);
    if (pointer != null) {
      _holdTimer = _clock.schedule(ComposerTokens.voiceHoldDelay, _armHold);
    }
    unawaited(_prepare(session));
  }

  Future<void> _prepare(_DictationSession session) async {
    try {
      await session.engine.start();
    } catch (error) {
      if (_session == session) {
        _complete(
          error is SpeechException ? error.kind : SpeechErrorKind.service,
        );
        unawaited(session.engine.cancel());
      }
      return;
    }
    if (_session != session || session.error != null || !listening) return;
    _readyAt = _clock.elapsed;
    if (_origin == null) {
      _lock();
    } else if (_wantsHold) {
      _setPhase(DictationPhase.hold);
    } else {
      // Start recognizes audio immediately, even during the tap/hold window.
      _setPhase(DictationPhase.press);
    }
    _tick();
  }

  void _armHold() {
    _wantsHold = true;
    _holdTimer?.cancel();
    if (_readyAt != null) _setPhase(DictationPhase.hold);
  }

  void move(Offset pointer) {
    final origin = _origin;
    if (origin == null || !listening || _retracting) return;
    _pointer = pointer;
    final delta = pointer - origin;
    if (!_wantsHold && delta.distance > ComposerTokens.voiceDragSlop) {
      _armHold();
    }
    _pull = _wantsHold ? voicePullDistance(-delta.dy) : 0;
    _detached = voiceDetached(_pull, previous: _detached);
    _publish();
  }

  void release({bool interrupted = false}) {
    if (_origin == null || !listening) return;
    final detached = _detached;
    final held =
        _wantsHold ||
        _clock.elapsed - _pressedAt! >= ComposerTokens.voiceHoldDelay;
    if (detached && !interrupted) {
      _cancel(fly: true);
    } else if (!interrupted &&
        _presentations > 0 &&
        held &&
        _pull > VoiceGooTokens.retractReleaseDistance) {
      _holdTimer?.cancel();
      _origin = _pointer = null;
      _retracting = true;
      _publish();
    } else if (_readyAt == null) {
      _clearGesture();
      _publish();
    } else if (held || interrupted) {
      finish();
    } else {
      _clearGesture();
      _lock();
    }
  }

  void interrupt() {
    if (!listening) return;
    if (_readyAt == null && !_retracting) {
      _clearGesture();
      _publish();
    } else {
      finish();
    }
  }

  void attachPresentation() => _presentations++;

  void detachPresentation() {
    if (_disposed || --_presentations > 0) return;
    if (_retracting) finish();
    if (_phase == DictationPhase.canceling) completeCancel();
  }

  void completeRetraction() {
    if (_retracting) finish();
  }

  void toggle() {
    if (listening) {
      finish();
    } else if (!active) {
      start();
    }
  }

  void _lock() {
    final session = _session!;
    session.handsFreeVolume = HandsFreeVolume(_clock.elapsed);
    _setPhase(DictationPhase.locked);
    _armSilence();
    if (session.lastRecognized.isNotEmpty) _armTextSilence();
  }

  void _armSilence() {
    if (_phase != DictationPhase.locked) return;
    _silenceTimer?.cancel();
    _silenceTimer = _clock.schedule(_silence, finish);
  }

  void _armTextSilence() {
    if (_phase != DictationPhase.locked) return;
    _textSilenceTimer?.cancel();
    _textSilenceTimer = _clock.schedule(_silence, finish);
  }

  void _tick() {
    final elapsed = listeningElapsed;
    final previous = _seconds;
    _seconds = elapsed.inSeconds;
    if (elapsed >= _limit) {
      if (_detached) {
        _cancel(fly: true);
      } else {
        _hitLimit = true;
        finish();
      }
      return;
    }
    if (_seconds != previous) {
      switch (_seconds) {
        case VoiceTokens.warningSecond:
          unawaited(HapticFeedback.lightImpact());
        case 57 || 58 || 59:
          unawaited(HapticFeedback.selectionClick());
      }
    }
    _tickTimer = _clock.schedule(
      Duration(seconds: _seconds + 1) - elapsed,
      _tick,
    );
    _publish();
  }

  void finish() {
    final session = _session;
    if (session == null || !listening) return;
    final ready = _readyAt != null;
    _clearTimers();
    _clearGesture();
    if (!ready) {
      _complete(null, silentIfEmpty: false);
    } else {
      _setPhase(DictationPhase.finalizing);
    }
    unawaited(session.engine.stop());
  }

  void _streamClosed(_DictationSession session) {
    if (++session.closedStreams == 2 && _session == session) {
      _complete(session.error);
    }
  }

  void _complete(SpeechErrorKind? error, {bool silentIfEmpty = true}) {
    _endSession();
    if (!_hasWritten) _inserted = TextRange.empty;
    final phase = switch (error) {
      SpeechErrorKind.permission => DictationPhase.errorPermission,
      SpeechErrorKind.network => DictationPhase.errorNetwork,
      SpeechErrorKind.busy => DictationPhase.errorBusy,
      SpeechErrorKind.silent => DictationPhase.errorSilent,
      SpeechErrorKind.service => DictationPhase.errorUnavailable,
      null when canUndo => DictationPhase.review,
      null when silentIfEmpty => DictationPhase.errorSilent,
      null => DictationPhase.idle,
    };
    _setPhase(phase);
  }

  void cancel() => _cancel(fly: false);

  void _cancel({required bool fly}) {
    if (!active && !canUndo) return;
    final session = _session;
    _endSession(keepGesture: fly);
    _flyCancel = fly && _presentations > 0;
    _holdCancelBar = _flyCancel;
    // Publish before replacing the range so the overlay can capture its
    // last laid-out glyph positions synchronously.
    _setPhase(DictationPhase.canceling);
    if (_hasWritten) {
      _replace('');
    } else if (_inserted.isValid) {
      _write(
        editor.value.copyWith(
          selection: TextSelection.collapsed(offset: _inserted.start),
          composing: TextRange.empty,
        ),
      );
    }
    if (_presentations == 0) {
      _cancelTimer = _clock.schedule(VoiceTokens.plainUndo, completeCancel);
    }
    if (session != null) unawaited(session.engine.cancel());
  }

  void releaseCancelBar() {
    if (!_holdCancelBar) return;
    _holdCancelBar = false;
    _clearGesture();
    _publish();
  }

  void completeCancel() {
    if (_phase == DictationPhase.canceling) _forgetText();
  }

  void dismissReview() {
    if (!active && _phase != DictationPhase.idle) _forgetText();
  }

  void retry() {
    cancel();
    start();
  }

  void _replace(String text) {
    final start = _inserted.start;
    final value = editor.text.replaceRange(start, _inserted.end, text);
    _inserted = TextRange(start: start, end: start + text.length);
    _hasWritten = true;
    _write(
      TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: _inserted.end),
      ),
    );
  }

  void _write(TextEditingValue value) {
    _writing = true;
    try {
      editor.value = value;
    } finally {
      _writing = false;
    }
  }

  void _editorChanged() {
    final edit = editor.value;
    final textChanged = _lastEdit.text != edit.text;
    final composingChanged = _lastEdit.composing != edit.composing;
    _lastEdit = edit;
    if (_writing || _phase == DictationPhase.idle) return;
    // Wait until the editor has applied the IME value before publishing idle.
    // In review, composing and selection syncs keep the undo range valid.
    if (!textChanged && !(active && composingChanged)) return;
    final session = _session;
    _endSession();
    _forgetText();
    // The displayed transcript is now ordinary text. Discard pending results.
    if (session != null) unawaited(session.engine.cancel());
  }

  void _forgetText() {
    _cancelTimer?.cancel();
    _holdCancelBar = false;
    _clearGesture();
    _text = const SpeechText(finalized: '', interim: '');
    _inserted = TextRange.empty;
    _hasWritten = false;
    _hitLimit = false;
    _setPhase(DictationPhase.idle);
  }

  void _endSession({bool keepGesture = false}) {
    final session = _session;
    _session = null;
    for (final subscription in session?.subscriptions ?? const []) {
      unawaited(subscription.cancel());
    }
    _clearTimers();
    if (keepGesture) {
      _holdTimer?.cancel();
    } else {
      _clearGesture();
    }
    _readyAt = null;
    _volume = 0;
  }

  void _clearTimers() {
    _tickTimer?.cancel();
    _silenceTimer?.cancel();
    _textSilenceTimer?.cancel();
  }

  void _clearGesture() {
    _holdTimer?.cancel();
    _origin = _pointer = null;
    _pressedAt = null;
    _pull = 0;
    _detached = false;
    _retracting = false;
  }

  void _setPhase(DictationPhase phase) {
    if (phase != DictationPhase.canceling) _flyCancel = false;
    if (phase != _phase) {
      _statusTimer?.cancel();
      if (phase == DictationPhase.errorSilent) {
        _statusTimer = _clock.schedule(VoiceTokens.silentStatus, _forgetText);
      }
    }
    _phase = phase;
    _publish();
  }

  void _publish() {
    value = (
      phase: _phase,
      pointer: _pointer,
      pull: _pull,
      detached: _detached,
      retracting: _retracting,
      holdBar: _holdCancelBar,
      volume: _volume,
      seconds: _seconds,
      hitLimit: _hitLimit,
      text: _text,
      insertedRange: _hasWritten ? _inserted : TextRange.empty,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _statusTimer?.cancel();
    _cancelTimer?.cancel();
    editor.removeListener(_editorChanged);
    final session = _session;
    _endSession();
    if (session != null) unawaited(session.engine.cancel());
    visual.dispose();
    super.dispose();
  }
}

class _DictationSession {
  final SpeechEngine engine;
  final subscriptions = <StreamSubscription<dynamic>>[];
  SpeechErrorKind? error;
  int closedStreams = 0;
  String lastRecognized = '';
  HandsFreeVolume? handsFreeVolume;

  _DictationSession(this.engine);
}
