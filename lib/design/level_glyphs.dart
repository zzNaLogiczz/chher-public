import 'dart:math' as math;
import 'dart:ui';

/// Paths on the approved 24 × 24 grid, copied from glyphs.js.
final Map<String, Map<String, String>> levelGlyphSources = {
  'ghost': {
    'f':
        'M5.5 10.5a6.5 6.5 0 0 1 13 0V19a2.17 2.17 0 0 1-4.33 0a2.17 2.17 0 0 1-4.34 0A2.17 2.17 0 0 1 5.5 19Z',
    's':
        'M5.5 10.5a6.5 6.5 0 0 1 13 0V19a2.17 2.17 0 0 1-4.33 0a2.17 2.17 0 0 1-4.34 0A2.17 2.17 0 0 1 5.5 19Z',
    'd':
        'M9.6 10.3a1.15 1.15 0 1 0 0 2.3a1.15 1.15 0 1 0 0-2.3Z M14.4 10.3a1.15 1.15 0 1 0 0 2.3a1.15 1.15 0 1 0 0-2.3Z',
  },
  'feather': {
    'f': 'M19.2 4.8Q8.6 6.2 6.6 17.4Q17.8 15.4 19.2 4.8Z',
    's': 'M19.2 4.8Q8.6 6.2 6.6 17.4Q17.8 15.4 19.2 4.8Z M4.4 19.6 14.6 9.4',
  },
  'halo': {
    'f': levelStar4(12, 15, 5.6),
    's':
        'M5.4 5.6a6.6 2.3 0 1 0 13.2 0a6.6 2.3 0 1 0-13.2 0Z ${levelStar4(12, 15, 5.6)}',
  },
  'wings': {
    'f':
        'M11 11C9.6 8.9 6.8 7.5 3 7.7c.6 1.6 1.6 2.8 3 3.4-.9.3-1.8.3-2.7.2.9 1.7 2.3 2.7 4 3-.6.5-1.4.8-2.3.9 1.9 1.4 4.1 1.7 6.4 1Z M13 11c1.4-2.1 4.2-3.5 8-3.3-.6 1.6-1.6 2.8-3 3.4.9.3 1.8.3 2.7.2-.9 1.7-2.3 2.7-4 3 .6.5 1.4.8 2.3.9-1.9 1.4-4.1 1.7-6.4 1Z',
    's':
        'M11 11C9.6 8.9 6.8 7.5 3 7.7c.6 1.6 1.6 2.8 3 3.4-.9.3-1.8.3-2.7.2.9 1.7 2.3 2.7 4 3-.6.5-1.4.8-2.3.9 1.9 1.4 4.1 1.7 6.4 1Z M13 11c1.4-2.1 4.2-3.5 8-3.3-.6 1.6-1.6 2.8-3 3.4.9.3 1.8.3 2.7.2-.9 1.7-2.3 2.7-4 3 .6.5 1.4.8 2.3.9-1.9 1.4-4.1 1.7-6.4 1Z M9.3 4.6a2.7 1 0 1 0 5.4 0a2.7 1 0 1 0-5.4 0Z',
  },
  'scepter': {
    'f': 'M12 2.6a3.3 3.3 0 1 0 0 6.6a3.3 3.3 0 1 0 0-6.6Z',
    's':
        'M12 2.6a3.3 3.3 0 1 0 0 6.6a3.3 3.3 0 1 0 0-6.6Z M8.8 11.2h6.4 M12 9.2v10.4',
    'd':
        'M12 19.4a1.5 1.5 0 1 0 0 3a1.5 1.5 0 1 0 0-3Z M12 4.6l.55 1.25 1.25.55-1.25.55L12 8.2l-.55-1.25-1.25-.55 1.25-.55Z',
  },
  'shield': {
    'f': 'M12 3 5 5.8v5.4c0 4.5 3 8.3 7 9.8 4-1.5 7-5.3 7-9.8V5.8Z',
    's': 'M12 3 5 5.8v5.4c0 4.5 3 8.3 7 9.8 4-1.5 7-5.3 7-9.8V5.8Z',
    'd': 'M12 8.2l1.1 2.6 2.6 1.1-2.6 1.1L12 15.6l-1.1-2.6-2.6-1.1 2.6-1.1Z',
  },
  'bolt': {
    'f': 'M13.4 2.8 5.6 13.2h5.8l-1.6 8 7.8-10.6h-5.8l1.6-7.8Z',
    's': 'M13.4 2.8 5.6 13.2h5.8l-1.6 8 7.8-10.6h-5.8l1.6-7.8Z',
  },
  'crown': {
    'f': 'M4 8.6l4 3.4L12 6l4 6 4-3.4-1.6 8.6H5.6Z',
    's': 'M4 8.6l4 3.4L12 6l4 6 4-3.4-1.6 8.6H5.6Z M5.8 20h12.4',
    'd':
        'M12 2.9a1.15 1.15 0 1 0 0 2.3a1.15 1.15 0 1 0 0-2.3Z M4 5.9a1.05 1.05 0 1 0 0 2.1a1.05 1.05 0 1 0 0-2.1Z M20 5.9a1.05 1.05 0 1 0 0 2.1a1.05 1.05 0 1 0 0-2.1Z',
  },
  'throne': {
    'f': 'M12 7.8a4.2 4.2 0 1 0 0 8.4a4.2 4.2 0 1 0 0-8.4Z',
    's':
        'M12 3.4a8.6 8.6 0 1 0 0 17.2a8.6 8.6 0 1 0 0-17.2Z M12 7.8a4.2 4.2 0 1 0 0 8.4a4.2 4.2 0 1 0 0-8.4Z $_spokes',
    'd': 'M12 10.6a1.4 1.4 0 1 0 0 2.8a1.4 1.4 0 1 0 0-2.8Z',
  },
  'eye': {
    'f':
        'M2.6 13C4.6 9.6 8 7.4 12 7.4s7.4 2.2 9.4 5.6c-2 3.4-5.4 5.6-9.4 5.6S4.6 16.4 2.6 13Z',
    's':
        'M2.6 13C4.6 9.6 8 7.4 12 7.4s7.4 2.2 9.4 5.6c-2 3.4-5.4 5.6-9.4 5.6S4.6 16.4 2.6 13Z M12 9.9a3.1 3.1 0 1 0 0 6.2a3.1 3.1 0 1 0 0-6.2Z M12 2.4v2.2 M6.2 3.8l1.1 1.8 M17.8 3.8l-1.1 1.8',
    'd': 'M12 11.7a1.3 1.3 0 1 0 0 2.6a1.3 1.3 0 1 0 0-2.6Z',
  },
  'flame': {
    'f':
        'M12.3 2.6c.7 3-.7 5-2.4 6.6C8 11.1 6.3 12.9 6.3 15.5c0 3.2 2.6 5.6 5.7 5.6s5.7-2.4 5.7-5.6c0-2.1-.9-3.9-2.2-5.3-.3 1.3-1 2.3-2 2.9.4-3.6-.3-7.1-1.2-10.5Z',
    's':
        'M12.3 2.6c.7 3-.7 5-2.4 6.6C8 11.1 6.3 12.9 6.3 15.5c0 3.2 2.6 5.6 5.7 5.6s5.7-2.4 5.7-5.6c0-2.1-.9-3.9-2.2-5.3-.3 1.3-1 2.3-2 2.9.4-3.6-.3-7.1-1.2-10.5Z',
    'd':
        'M12 19.1c-1.3 0-2.2-.9-2.2-2.1 0-1.1.8-2 1.8-2.9.2.8.6 1.4 1.3 1.7.3-.5.4-.9.6-1.3.6.7.8 1.5.8 2.5 0 1.2-1 2.1-2.3 2.1Z',
  },
  'imp': {
    'f': 'M12 8.4a6 6 0 1 0 0 12a6 6 0 1 0 0-12Z',
    's':
        'M12 8.4a6 6 0 1 0 0 12a6 6 0 1 0 0-12Z M7.9 10.2C6.5 8.8 5.9 6.8 6.2 4.6c1.6.8 2.9 2 3.7 3.5 M16.1 10.2c1.4-1.4 2-3.4 1.7-5.6-1.6.8-2.9 2-3.7 3.5 M9.6 16.8c1.4 1.3 3.4 1.3 4.8 0',
    'd': 'M8.6 12.9l2.4.9-.3.9-2.2-.6Z M15.4 12.9l-2.4.9.3.9 2.2-.6Z',
  },
  'archfiend': {
    'f': 'M12 9.6a5 5 0 1 0 0 10a5 5 0 1 0 0-10Z',
    's':
        'M12 9.6a5 5 0 1 0 0 10a5 5 0 1 0 0-10Z M8.4 10.6C6.4 9 5.4 6.6 5.6 3.6c2 1 3.6 2.6 4.6 4.6 M15.6 10.6c2-1.6 3-4 2.8-7-2 1-3.6 2.6-4.6 4.6 M7.2 14.4C5.6 12.8 3.6 12.4 1.6 12.8c.8.9 1.2 2 1.2 3.1.9-.5 1.8-.6 2.7-.4-.1.9.1 1.8.6 2.6 M16.8 14.4c1.6-1.6 3.6-2 5.6-1.6-.8.9-1.2 2-1.2 3.1-.9-.5-1.8-.6-2.7-.4.1.9-.1 1.8-.6 2.6 M10 17.2c1.2 1 2.8 1 4 0',
    'd': 'M9.2 13.4l2.2.8-.3.8-2-.5Z M14.8 13.4l-2.2.8.3.8 2-.5Z',
  },
  'demoncrown': {
    'f':
        'M5.2 18 4.2 9.6l3.6 3.1L10.2 6.6 12 10.8l1.8-4.2 2.4 6.1 3.6-3.1-1 8.4Z',
    's':
        'M5.2 18 4.2 9.6l3.6 3.1L10.2 6.6 12 10.8l1.8-4.2 2.4 6.1 3.6-3.1-1 8.4Z M5.2 20.4h13.6 M4.2 9.6C3.2 7.8 3.2 5.8 4.4 4c.5 1.8 1.4 3.2 2.8 4.2 M19.8 9.6c1-1.8 1-3.8-.2-5.6-.5 1.8-1.4 3.2-2.8 4.2',
    'd': 'M12 13.4l1.3 1.5-1.3 1.5-1.3-1.5Z',
  },
  'morningstar': {
    'f': levelStar4(12, 12, 9.6),
    's':
        '${levelStar4(12, 12, 9.6)} M6.6 6.6l2 2 M17.4 6.6l-2 2 M6.6 17.4l2-2 M17.4 17.4l-2-2',
    'd': 'M12 10.7a1.3 1.3 0 1 0 0 2.6a1.3 1.3 0 1 0 0-2.6Z',
  },
  'trident': {
    's': 'M12 6v15.6 M6.6 5.2v3.6a3 3 0 0 0 3 3h4.8a3 3 0 0 0 3-3V5.2',
    'd': 'M12 2l1.7 3.4h-3.4Z M6.6 2.2l1.6 3h-3.2Z M17.4 2.2l1.6 3h-3.2Z',
  },
};

String levelStar4(num cx, num cy, num r) {
  final k = r * .28;
  return 'M$cx ${cy - r}C${cx + k * .4} ${cy - k} ${cx + k} ${cy - k * .4} ${cx + r} $cy'
      'C${cx + k} ${cy + k * .4} ${cx + k * .4} ${cy + k} $cx ${cy + r}'
      'C${cx - k * .4} ${cy + k} ${cx - k} ${cy + k * .4} ${cx - r} $cy'
      'C${cx - k} ${cy - k * .4} ${cx - k * .4} ${cy - k} $cx ${cy - r}Z';
}

final _spokes = List.generate(6, (i) {
  final a = (i * 60 + 30) * math.pi / 180;
  final c = math.cos(a), s = math.sin(a);
  return 'M${(12 + c * 4.2).toStringAsFixed(2)} ${(12 + s * 4.2).toStringAsFixed(2)}'
      'L${(12 + c * 7.6).toStringAsFixed(2)} ${(12 + s * 7.6).toStringAsFixed(2)}';
}).join();

class LevelGlyph {
  LevelGlyph(Map<String, String> source)
    : f = source['f'] == null ? null : parseLevelPath(source['f']!),
      s = source['s'] == null ? null : parseLevelPath(source['s']!),
      d = source['d'] == null ? null : parseLevelPath(source['d']!);

  final Path? f, s, d;
}

abstract final class LevelGlyphs {
  static final _cache = <String, LevelGlyph>{};
  static LevelGlyph get(String key) =>
      _cache.putIfAbsent(key, () => LevelGlyph(levelGlyphSources[key]!));
}

final _pathCache = <String, Path>{};
final _pathToken = RegExp(
  r'[a-zA-Z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?',
);

/// Parses the commands used by the approved glyphs, once per source string.
Path parseLevelPath(String source) => _pathCache.putIfAbsent(source, () {
  final tokens = _pathToken.allMatches(source).map((m) => m[0]!).toList();
  final path = Path();
  var i = 0;
  var command = '';
  var previous = '';
  var current = Offset.zero;
  var start = Offset.zero;
  var cubicControl = Offset.zero;
  double number() {
    if (i >= tokens.length) {
      throw FormatException('Incomplete SVG path', source);
    }
    return double.parse(tokens[i++]);
  }

  bool isCommand(String token) => RegExp(r'^[a-zA-Z]$').hasMatch(token);
  while (i < tokens.length) {
    if (isCommand(tokens[i])) command = tokens[i++];
    if (command.isEmpty) throw FormatException('Missing SVG command', source);
    final relative = command == command.toLowerCase();
    final upper = command.toUpperCase();
    final origin = relative ? current : Offset.zero;
    Offset point() => origin + Offset(number(), number());
    switch (upper) {
      case 'M':
        current = point();
        path.moveTo(current.dx, current.dy);
        start = current;
        command = relative ? 'l' : 'L';
      case 'L':
        current = point();
        path.lineTo(current.dx, current.dy);
      case 'H':
        current = Offset(origin.dx + number(), current.dy);
        path.lineTo(current.dx, current.dy);
      case 'V':
        current = Offset(current.dx, origin.dy + number());
        path.lineTo(current.dx, current.dy);
      case 'C':
        final c1 = point(), c2 = point(), end = point();
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        cubicControl = c2;
        current = end;
      case 'S':
        final c1 = previous == 'C' || previous == 'S'
            ? current * 2 - cubicControl
            : current;
        final c2 = point(), end = point();
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
        cubicControl = c2;
        current = end;
      case 'Q':
        final control = point(), end = point();
        path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        current = end;
      case 'A':
        final rx = number(), ry = number(), rotation = number();
        final large = number(), sweep = number();
        if ((large != 0 && large != 1) || (sweep != 0 && sweep != 1)) {
          throw FormatException('Invalid SVG arc flag', source);
        }
        final end = point();
        path.arcToPoint(
          end,
          radius: Radius.elliptical(rx.abs(), ry.abs()),
          rotation: rotation,
          largeArc: large == 1,
          clockwise: sweep == 1,
        );
        current = end;
      case 'Z':
        path.close();
        current = start;
        command = '';
      default:
        throw FormatException('Unsupported SVG command $command', source);
    }
    previous = upper;
  }
  return path;
});
