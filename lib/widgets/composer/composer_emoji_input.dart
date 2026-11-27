import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';

import '../../data/smiley_store.dart';
import '../../design/composer_tokens.dart';
import '../../design/tokens.dart';
import 'composer_tool_strip.dart';
import 'emoji_panel.dart';
import 'smiley_editing_controller.dart';

/// Owns switching between the software keyboard and the forum smiley panel.
class ComposerEmojiInput {
  ComposerEmojiInput({
    required this.input,
    required this.focus,
    required this.onChanged,
    required this.store,
  }) {
    unawaited(_restore());
  }

  final SmileyEditingController input;
  final FocusNode focus;
  final VoidCallback onChanged;
  final SmileyStore store;

  static final _recentKeyboardHeights = Expando<double>();
  FlutterView? _view;
  double _keyboardHeight = 0;
  double _panelHeight = 0;
  Timer? _keyboardHandoff;
  bool _disposed = false;
  bool _loading = false;
  bool _failed = false;

  bool isOpen = false;
  bool get reservesSpace => isOpen || _keyboardHandoff != null;

  /// The host keeps its normal IME avoidance. We reserve only the difference.
  /// Read media at host level, before Scaffold or a sheet consumes the inset.
  void updateMedia(BuildContext context) {
    _view = View.of(context);
    final media = MediaQuery.of(context);
    final previous = _keyboardHeight;
    _keyboardHeight = media.viewInsets.bottom;
    if (!reservesSpace && _keyboardHeight > 0) {
      // Ignore descending IME animation frames, which aren't a usable height.
      if (_keyboardHeight >= previous) {
        _recentKeyboardHeights[_view!] = _keyboardHeight;
      }
    }
    if (_keyboardHandoff == null || previous == _keyboardHeight) return;
    if (_keyboardHeight >= _panelHeight) {
      _endHandoff();
    } else {
      _waitForKeyboard();
    }
  }

  Future<void> _restore() async {
    final cached = await store.readCache();
    if (_disposed || cached == null || input.catalog != null) return;
    input.catalog = cached;
    onChanged();
  }

  Future<void> _load() async {
    if (_loading || input.catalog != null) return;
    _loading = true;
    _failed = false;
    onChanged();
    try {
      final catalog = await store.load();
      if (!_disposed) input.catalog = catalog;
    } catch (_) {
      _failed = true;
    } finally {
      _loading = false;
      if (!_disposed) onChanged();
    }
  }

  void _open() {
    _endHandoff();
    final view = _view;
    _panelHeight = _keyboardHeight > 0
        ? _keyboardHeight
        : (view == null ? null : _recentKeyboardHeights[view]) ??
              ComposerTokens.emojiHeight;
    isOpen = true;
    focus.unfocus();
    onChanged();
    unawaited(_load());
  }

  void showKeyboard() {
    if (!isOpen) return;
    isOpen = false;
    if (_keyboardHeight < _panelHeight) _waitForKeyboard();
    focus.requestFocus();
    onChanged();
  }

  void dismiss() {
    if (!reservesSpace) return;
    _endHandoff();
    isOpen = false;
    onChanged();
  }

  void _waitForKeyboard() {
    _keyboardHandoff?.cancel();
    _keyboardHandoff = Timer(ComposerTokens.emojiKeyboardHandoff, () {
      _endHandoff();
      if (_view case final view? when _keyboardHeight > 0) {
        _recentKeyboardHeights[view] = _keyboardHeight;
      }
      onChanged();
    });
  }

  void _endHandoff() {
    _keyboardHandoff?.cancel();
    _keyboardHandoff = null;
  }

  Widget tool({required bool enabled}) => ComposerEmojiTool(
    selected: isOpen,
    onPressed: !enabled
        ? null
        : isOpen
        ? showKeyboard
        : _open,
  );

  Widget dock(BuildContext context, {required bool enabled}) {
    if (!reservesSpace) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final limit =
        media.size.height -
        media.viewPadding.top -
        ComposerTokens.emojiComposerClearance;
    final height = math.min(_panelHeight, math.max(_keyboardHeight, limit));
    final extra = height - _keyboardHeight;
    if (extra <= 0) return const SizedBox.shrink();
    final colors = ComposerTokens.emojiColors(AppTokens.of(context));
    return SizedBox(
      height: extra,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: height,
          maxHeight: height,
          child: isOpen
              ? EmojiPanel(
                  catalog: input.catalog,
                  onInsert: enabled ? input.insertSmiley : null,
                  onDelete: enabled ? input.deleteBeforeCursor : null,
                  onRetry: enabled ? _load : null,
                  failed: _failed,
                )
              : ColoredBox(color: colors.background),
        ),
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _endHandoff();
  }
}
