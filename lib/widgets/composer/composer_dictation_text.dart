import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../design/tokens.dart';
import '../../design/voice_text_tokens.dart';
import '../../design/voice_tokens.dart';
import 'dictation_controller.dart';
import 'smiley_editing_controller.dart';
import 'voice_fly_motion.dart';

typedef _T = VoiceTextTokens;

class ComposerDictationText extends StatefulWidget {
  const ComposerDictationText({
    super.key,
    required this.dictation,
    required this.editor,
    required this.field,
  });

  final DictationController dictation;
  final SmileyEditingController editor;
  final Widget Function({bool hideHint, bool listening}) field;

  @override
  State<ComposerDictationText> createState() => _ComposerDictationTextState();
}

typedef _Letter = ({String text, double begin, bool commit});
typedef _Ink = ({ui.Image image, Rect bounds});
typedef _PositionedInk = ({_Ink ink, Rect box});
typedef _Flight = ({
  _PositionedInk glyph,
  double delay,
  double side,
  double bend,
  double rotation,
  Color color,
});

class _ComposerDictationTextState extends State<ComposerDictationText>
    with SingleTickerProviderStateMixin {
  static final _riseCurve = Cubic(
    _T.riseCurve.$1,
    _T.riseCurve.$2,
    _T.riseCurve.$3,
    _T.riseCurve.$4,
  );
  final _fieldKey = GlobalKey();
  final _textKey = GlobalKey();
  final _flyKey = GlobalKey();
  final _flyOverlay = OverlayPortalController();
  final _repaint = ValueNotifier(0);
  final _letters = <int, _Letter>{};
  final _ink = <(String, TextDirection), _Ink>{};
  final _positions = <int, _PositionedInk?>{};
  late final Ticker _ticker;
  late AppTokens _tokens;
  bool _reduced = false;
  String _transcript = '';
  int _rangeStart = -1;
  int _finishedEnd = -1;
  bool _listening = false;
  bool _cut = false;
  bool _canceling = false;
  bool _hideHint = false;
  double _dpr = 1;
  double _now = 0;
  double _startTime = 0;
  double _lastEnd = 0;
  List<_Flight> _flights = const [];
  RenderEditable? _render;
  ViewportOffset? _scroll;
  (TextStyle?, TextScaler, Locale?, double)? _inkStyle;
  (InlineSpan?, Size, double)? _positionsLayout;
  int? _caretOffset;
  Rect? _caret;

  void _requestPaint() => _repaint.value++;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tokens = AppTokens.of(context);
    _dpr = MediaQuery.devicePixelRatioOf(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced != reduced && _letters.isNotEmpty) _clearLetters();
    _reduced = reduced;
    _syncAppearance(notify: false);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _listen(widget.dictation, true);
  }

  @override
  void didUpdateWidget(covariant ComposerDictationText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dictation == widget.dictation) return;
    _listen(oldWidget.dictation, false);
    oldWidget.editor.setVoiceTextRanges(const [], notify: false);
    _forget();
    _listen(widget.dictation, true);
    _sync();
  }

  void _listen(DictationController controller, bool attach) {
    if (attach) {
      controller.addListener(_sync);
      controller.visual.addListener(_visualChanged);
    } else {
      controller.removeListener(_sync);
      controller.visual.removeListener(_visualChanged);
    }
  }

  void _visualChanged() {
    if ((_listening && !_reduced) || _flights.isNotEmpty) {
      _requestPaint();
    }
  }

  void _clearLetters() {
    _ticker.stop();
    _letters.clear();
    _positions.clear();
  }

  void _forget() {
    _clearLetters();
    _transcript = '';
    _rangeStart = _finishedEnd = -1;
    _listening = _cut = _canceling = false;
    _flights = const [];
    _flyOverlay.hide();
    _clearInk();
  }

  void _sync() {
    final controller = widget.dictation;
    final frame = controller.value;
    final wasListening = _listening;
    final hadHiddenHint = _hideHint;
    if (frame.phase == DictationPhase.canceling) {
      if (_canceling) {
        if (_cut && !frame.holdBar) {
          _hideHint = false;
          _flights = const [];
          _flyOverlay.hide();
          _clearInk();
        }
      } else {
        _canceling = true;
        _flights = _prepFly(frame);
        if (_flights.isNotEmpty) _flyOverlay.show();
        _hideHint = _flights.isNotEmpty;
        _clearLetters();
        _listening = false;
        _transcript = '';
        _rangeStart = _finishedEnd = -1;
      }
    } else if (frame.phase == DictationPhase.idle || _canceling) {
      _forget();
      _hideHint = false;
    }
    if (!_canceling) {
      final range = frame.insertedRange;
      final next = frame.text.combined;
      final finalized = switch (frame.phase) {
        DictationPhase.review ||
        DictationPhase.errorNetwork ||
        DictationPhase.errorUnavailable => next.length,
        _ => frame.text.finalized.length,
      };
      final end = range.start + finalized;
      if (_transcript != next ||
          _rangeStart != range.start ||
          _finishedEnd != end) {
        _updateLetters(next, range.start, end);
      }
      _listening = controller.listening;
      _cut = frame.detached;
    }
    if (wasListening != _listening || hadHiddenHint != _hideHint) {
      setState(() {});
    }
    _syncAppearance();
    _requestPaint();
  }

  void _updateLetters(String next, int start, int end) {
    final previous = Map<int, _Letter>.of(_letters);
    _letters.clear();
    _positions.clear();
    var offset = start;
    var riseCount = 0;
    var commitCount = 0;
    if (start >= 0) {
      for (final letter in next.characters) {
        final commit = offset < end;
        final unchanged =
            start == _rangeStart &&
            offset - start + letter.length <= _transcript.length &&
            _transcript.startsWith(letter, offset - start) &&
            commit == (offset < _finishedEnd);
        if (unchanged) {
          final existing = previous[offset];
          if (existing != null && _endOf(existing) > _now) {
            _letters[offset] = existing;
          }
        } else if (!_reduced || !commit) {
          _letters[offset] = (
            text: letter,
            begin:
                _now +
                (_reduced
                    ? 0
                    : commit
                    ? commitCount++ * _T.commitStagger
                    : riseCount++ * _T.riseStagger),
            commit: commit,
          );
        }
        offset += letter.length;
      }
    }
    _transcript = next;
    _rangeStart = start;
    _finishedEnd = end;
    if (_letters.isNotEmpty) {
      _lastEnd = _letters.values.map(_endOf).reduce(math.max);
      if (!_ticker.isActive) {
        _startTime = _now;
        _ticker.start();
      }
    } else {
      _ticker.stop();
    }
  }

  double _duration(_Letter letter) => _reduced
      ? _T.reducedFade
      : letter.commit
      ? _T.commitDuration
      : _T.riseDuration;

  double _endOf(_Letter letter) => letter.begin + _duration(letter);

  void _tick(Duration elapsed) {
    _now = _startTime + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (_now >= _lastEnd) {
      _clearLetters();
      _syncAppearance();
      if (!_canceling) _clearInk();
    }
    _requestPaint();
  }

  void _syncAppearance({bool notify = true}) {
    final ranges = <VoiceTextRange>[];
    final review = switch (widget.dictation.value.phase) {
      DictationPhase.review ||
      DictationPhase.errorNetwork ||
      DictationPhase.errorUnavailable => _tokens.accentFill,
      _ => null,
    };
    void add(int start, int end, Color? color) {
      if (start >= end || (color == null && review == null)) return;
      final style = TextStyle(color: color, backgroundColor: review);
      if (ranges.isNotEmpty &&
          ranges.last.range.end == start &&
          ranges.last.style == style) {
        start = ranges.removeLast().range.start;
      }
      ranges.add((range: TextRange(start: start, end: end), style: style));
    }

    if (_rangeStart >= 0) {
      final end = _rangeStart + _transcript.length;
      final body = _cut ? _tokens.text.withValues(alpha: _T.cutOpacity) : null;
      final interim = _cut
          ? _tokens.text3.withValues(alpha: _T.cutOpacity)
          : _tokens.text3;
      void addStatic(int start, int stop) {
        add(start, math.min(stop, _finishedEnd), body);
        add(math.max(start, _finishedEnd), stop, interim);
      }

      var offset = _rangeStart;
      for (final MapEntry(key: start, value: letter) in _letters.entries) {
        addStatic(offset, start);
        offset = start + letter.text.length;
        add(start, offset, Colors.transparent);
      }
      addStatic(offset, end);
    }
    widget.editor.setVoiceTextRanges(ranges, notify: notify);
  }

  RenderEditable? _editable() {
    if (_render?.attached != true) {
      RenderEditable? find(RenderObject object) {
        if (object is RenderEditable) return object;
        RenderEditable? result;
        object.visitChildren((child) => result ??= find(child));
        return result;
      }

      final field = _fieldKey.currentContext?.findRenderObject();
      _render = field == null ? null : find(field);
    }
    final render = _render;
    if (render == null || !render.hasSize) return null;
    if (_scroll != render.offset) {
      _scroll?.removeListener(_requestPaint);
      _scroll = render.offset..addListener(_requestPaint);
    }
    final style = (render.text?.style, render.textScaler, render.locale, _dpr);
    if (_inkStyle != style) {
      _clearInk();
      _inkStyle = style;
    }
    return render;
  }

  void _clearInk() {
    for (final entry in _ink.values) {
      entry.image.dispose();
    }
    _ink.clear();
    _positions.clear();
  }

  _PositionedInk? _glyph(RenderEditable render, String char, int start) {
    if (char.trim().isEmpty) return null;
    final range = TextSelection(
      baseOffset: start,
      extentOffset: start + char.length,
    );
    final boxes = render.getBoxesForSelection(range);
    if (boxes.isEmpty) return null;
    final box = boxes.first;
    if (box.left == box.right ||
        !box.toRect().overlaps(Offset.zero & render.size)) {
      return null;
    }
    final ink = _ink.putIfAbsent((char, box.direction), () {
      final (style, scaler, locale, dpr) = _inkStyle!;
      final text = TextPainter(
        text: TextSpan(
          text: char,
          style: style?.copyWith(color: VoiceTokens.light),
        ),
        textDirection: box.direction,
        textScaler: scaler,
        locale: locale,
        maxLines: 1,
      )..layout();
      final glyph =
          text
              .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: char.length),
              )
              .firstOrNull
              ?.toRect() ??
          Rect.zero;
      final width = math.max(1, (text.width * dpr).ceil());
      final height = math.max(1, (text.height * dpr).ceil());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(dpr);
      text.paint(canvas, Offset.zero);
      text.dispose();
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      return (
        image: image,
        bounds: Rect.fromLTWH(
          -glyph.left,
          -glyph.top,
          width / dpr,
          height / dpr,
        ),
      );
    });
    return (ink: ink, box: box.toRect());
  }

  List<_Flight> _prepFly(DictationFrame frame) {
    final range = frame.insertedRange;
    final editable = _editable();
    if (range.isCollapsed || !range.isValid || editable == null) {
      return const [];
    }
    final painted =
        editable.text?.toPlainText(includeSemanticsLabels: false) ?? '';
    final chars = frame.text.combined.characters;
    final count = chars.length;
    final source = editable.localToGlobal(Offset.zero);
    final random = math.Random(11);
    final prepared = <_Flight>[];
    var start = range.start;
    for (final (index, char) in chars.indexed) {
      final side = random.nextDouble() < .5 ? -1.0 : 1.0;
      final bend = _T.flyBend + _T.flyBendRange * random.nextDouble();
      final rotation = (random.nextDouble() - .5) * _T.flyRotationRange;
      // The latest ASR result may have arrived since the editor last laid out.
      final glyph =
          start + char.length <= painted.length &&
              painted.startsWith(char, start)
          ? _glyph(editable, char, start)
          : null;
      if (glyph != null) {
        prepared.add((
          glyph: (ink: glyph.ink, box: glyph.box.shift(source)),
          delay: voiceFlyDelay(index, count),
          side: side,
          bend: bend,
          rotation: rotation,
          color: frame.detached || start < _finishedEnd
              ? _tokens.text
              : _tokens.text3,
        ));
      }
      start += char.length;
    }
    return prepared;
  }

  final _glyphPaint = Paint()..filterQuality = FilterQuality.low;
  final _cursorPaint = Paint();

  void _drawGlyph(Canvas canvas, _PositionedInk glyph, Color color) {
    if (color.a <= 0) return;
    final (:image, :bounds) = glyph.ink;
    _glyphPaint.colorFilter = ColorFilter.mode(color, BlendMode.srcIn);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      bounds.shift(glyph.box.topLeft),
      _glyphPaint,
    );
  }

  void _paintText(Canvas canvas, Size size) {
    if (_letters.isEmpty && !_listening) return;
    final render = _editable();
    final target = _textKey.currentContext?.findRenderObject();
    if (render == null || target is! RenderBox) return;
    final layout = (render.text, render.size, render.offset.pixels);
    if (_positionsLayout != layout) {
      _positionsLayout = layout;
      _positions.clear();
      _caretOffset = null;
    }
    final offset = target.globalToLocal(render.localToGlobal(Offset.zero));
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.clipRect(Offset.zero & render.size);
    final cut = _cut ? _T.cutOpacity : 1.0;
    final scaledEm = render.textScaler.scale(
      render.text?.style?.fontSize ?? render.preferredLineHeight,
    );
    for (final MapEntry(key: start, value: letter) in _letters.entries) {
      final glyph = _positions.putIfAbsent(
        start,
        () => _glyph(render, letter.text, start),
      );
      if (glyph == null) continue;
      final p = ((_now - letter.begin) / _duration(letter)).clamp(0.0, 1.0);
      if (_reduced) {
        _drawGlyph(
          canvas,
          glyph,
          _tokens.text3.withValues(alpha: cut * Curves.easeOut.transform(p)),
        );
      } else if (letter.commit) {
        final color = Color.lerp(
          _tokens.ai1,
          _tokens.text,
          Curves.easeOut.transform(p),
        )!;
        _drawGlyph(canvas, glyph, color.withValues(alpha: cut));
      } else {
        final e = _riseCurve.transform(p);
        final float = scaledEm * _T.riseHeight * (1 - e);
        final alpha = math.min(1.0, e / _T.riseAccentStop);
        final color = e < _T.riseAccentStop
            ? Color.lerp(_tokens.ai3, _tokens.ai1, alpha)!
            : Color.lerp(
                _tokens.ai1,
                _tokens.text3,
                (e - _T.riseAccentStop) / (1 - _T.riseAccentStop),
              )!;
        canvas.save();
        canvas.translate(0, float);
        _drawGlyph(canvas, glyph, color.withValues(alpha: cut * alpha));
        canvas.restore();
      }
    }
    if (_listening) {
      final selection = widget.editor.selection;
      final pos = _rangeStart >= 0
          ? _rangeStart + _transcript.length
          : selection.isValid
          ? selection.start
          : widget.editor.text.length;
      if (_caretOffset != pos) {
        _caretOffset = pos;
        _caret = render.getLocalRectForCaret(TextPosition(offset: pos));
      }
      final caret = _caret!;
      final height = scaledEm * _T.cursorHeight;
      final rect = Rect.fromLTWH(
        caret.left + _T.cursorGap,
        caret.center.dy - height / 2,
        _T.cursorWidth,
        height,
      );
      final volume = _reduced ? 0.0 : widget.dictation.visual.value.volume;
      final alpha =
          _T.cursorOpacity +
          (1 - _T.cursorOpacity) * math.min(1, volume * _T.cursorVolumeGain);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(_T.cursorRadius)),
        _cursorPaint..color = _tokens.ai1.withValues(alpha: alpha),
      );
    }
    canvas.restore();
  }

  void _paintFly(Canvas canvas, Size size) {
    final box = _flyKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final frame = widget.dictation.visual.value;
    final center = frame.dropCenter;
    final elapsed = frame.flyElapsed;
    final shift = -box.localToGlobal(Offset.zero);
    canvas.save();
    canvas.translate(shift.dx, shift.dy);
    for (final flight in _flights) {
      final glyph = flight.glyph;
      final point = glyph.box.center;
      if (center != null && elapsed != null && !_reduced) {
        final pose = voiceFlyPose(
          elapsed: elapsed,
          delay: flight.delay,
          x0: point.dx,
          y0: point.dy,
          x2: center.dx,
          y2: center.dy,
          side: flight.side,
          bend: flight.bend,
          rotation: flight.rotation,
        );
        if (pose.opacity <= 0) continue;
        canvas.save();
        canvas.translate(pose.x, pose.y);
        canvas.rotate(pose.rotation);
        canvas.scale(pose.scale);
        canvas.translate(-point.dx, -point.dy);
        _drawGlyph(
          canvas,
          glyph,
          flight.color.withValues(alpha: _T.cutOpacity * pose.opacity),
        );
        canvas.restore();
      } else {
        final duration = _reduced ? _T.reducedFade : _T.cancelFade;
        final p = ((frame.cancelElapsed ?? 0) / duration).clamp(0.0, 1.0);
        final base = _cut ? _T.cutOpacity : 1.0;
        _drawGlyph(
          canvas,
          glyph,
          flight.color.withValues(alpha: base * (1 - p)),
        );
      }
    }
    canvas.restore();
  }

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _flyOverlay,
    overlayLocation: OverlayChildLocation.rootOverlay,
    overlayChildBuilder: (_) => IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox.expand(
          child: RepaintBoundary(
            child: CustomPaint(
              key: _flyKey,
              painter: _TextPaint(_paintFly, _repaint),
            ),
          ),
        ),
      ),
    ),
    child: Stack(
      children: [
        KeyedSubtree(
          key: _fieldKey,
          child: widget.field(hideHint: _hideHint, listening: _listening),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: _textKey,
                  painter: _TextPaint(_paintText, _repaint),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _listen(widget.dictation, false);
    widget.editor.setVoiceTextRanges(const [], notify: false);
    _scroll?.removeListener(_requestPaint);
    _ticker.dispose();
    _repaint.dispose();
    _clearInk();
    super.dispose();
  }
}

class _TextPaint extends CustomPainter {
  _TextPaint(this.draw, Listenable repaint) : super(repaint: repaint);

  final void Function(Canvas, Size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(_TextPaint oldDelegate) => true;
}
