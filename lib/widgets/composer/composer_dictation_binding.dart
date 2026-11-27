import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../di.dart';
import '../../voice/speech_engine.dart';
import 'dictation_controller.dart';
import 'smiley_editing_controller.dart';
import 'voice_bar.dart';

/// Shares availability and interruption handling across the composer hosts.
/// Only toolbar visibility and editor locking rebuild the host.
class ComposerDictationBinding with WidgetsBindingObserver {
  final VoidCallback onChanged;
  final SmileyEditingController _editor;
  late final DictationController controller;
  SpeechEngineKind _kind = SpeechEngineKind.none;
  bool _wasVisible = false;
  bool _wasActive = false;
  bool _wasExpanded = false;
  bool _disposed = false;

  ComposerDictationBinding({
    required SmileyEditingController editor,
    required this.onChanged,
  }) : _editor = editor {
    controller = DictationController(
      editor: editor,
      createEngine: () => createSpeechEngine(_kind),
    )..addListener(_sync);
    editor.editingGuard = controller.editingGuard;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  bool get active => controller.editorLocked;
  bool get barExpanded => controller.barExpanded;
  bool get _visible => _kind != SpeechEngineKind.none;

  Future<void> _load() async {
    final availability = await queryVoiceAvailability();
    if (_disposed) return;
    _kind = availability.kind;
    _sync();
  }

  void _sync() {
    if (_wasVisible == _visible &&
        _wasActive == active &&
        _wasExpanded == barExpanded) {
      return;
    }
    _wasVisible = _visible;
    _wasActive = active;
    _wasExpanded = barExpanded;
    onChanged();
  }

  Widget? bar({required bool enabled}) => _visible
      ? TextFieldTapRegion(
          child: VoiceBar(controller: controller, enabled: enabled),
        )
      : null;

  Widget status({bool chat = false, required bool enabled}) =>
      VoiceStatus(controller: controller, chat: chat, enabled: enabled);

  Widget scope(Widget child, {required bool enabled}) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (enabled &&
          event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          (controller.active || controller.canUndo)) {
        controller.cancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) controller.interrupt();
  }

  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_sync);
    _editor.editingGuard = null;
    controller.dispose();
  }
}
