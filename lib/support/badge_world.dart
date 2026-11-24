// Port of the Chhers prototype's badge-physics.js, under the repository LICENSE.
// Units are pixels, seconds and radians. Screen axes point right, down and out.
import 'dart:math' as math;
import 'dart:typed_data';

const badgeSubstep = 1 / 600;

class BadgePhysicsConfig {
  const BadgePhysicsConfig({
    this.strapSegments = 14,
    this.strapParticleMass = 0.012,
    this.bendStiffness = 0.04,
    this.strapDrag = 2.0,
    this.cardDrag = 0.3,
    this.cardAngularDrag = 0.6,
    this.settleDrag = 1.6,
    this.settleSpeed = 60,
    this.pressFriction = 0.8,
    this.restitutionCard = 0.38,
    this.restitutionWall = 0.3,
    this.restitutionStrap = 0.22,
    this.introDamping = 0.3,
    this.frictionCard = 0.12,
    this.frictionWall = 0.2,
    this.yawFreq = 1.2,
    this.yawDamping = 0.6,
    this.flipKick = 3,
    this.broadside = 3e-6,
    this.pitchFreq = 2.6,
    this.pitchDamping = 0.22,
    this.pitchMax = 0.5,
    this.pitchLean = 0.2,
    this.pitchShake = 0.006,
    this.pitchInertia = 0.6,
    this.liftPitch = 0.14,
    this.hitEventSpeed = 420,
    this.calmSpeed = 6,
    this.maxPush = 2,
    this.grabStiffness = 0.18,
    this.grabMaxMove = 8,
    this.maxSpeed = 7000,
    this.maxSpin = 40,
  });

  final int strapSegments;
  final double strapParticleMass, bendStiffness, strapDrag, cardDrag;
  final double cardAngularDrag, settleDrag, settleSpeed, pressFriction;
  final double restitutionCard, restitutionWall, restitutionStrap, introDamping;
  final double frictionCard, frictionWall, yawFreq, yawDamping, flipKick;
  final double broadside, pitchFreq, pitchDamping, pitchMax, pitchLean;
  final double pitchShake, pitchInertia, liftPitch, hitEventSpeed, calmSpeed;
  final double maxPush, grabStiffness, grabMaxMove, maxSpeed, maxSpin;
}

double _hypot(double x, double y) {
  final largest = math.max(x.abs(), y.abs());
  if (largest == 0 || largest.isInfinite) return largest;
  final ratio = math.min(x.abs(), y.abs()) / largest;
  return math.sqrt(1 + ratio * ratio) * largest;
}

double _cross(double ax, double ay, double bx, double by) => ax * by - ay * bx;

class BadgeStrap {
  BadgeStrap(this.ax, this.ay, this.length, this.n, double mass)
    : seg = length / n,
      x = Float64List(n + 1),
      y = Float64List(n + 1),
      _px = Float64List(n + 1),
      _py = Float64List(n + 1),
      vx = Float64List(n + 1),
      vy = Float64List(n + 1),
      _w = Float64List(n + 1) {
    for (var i = 0; i <= n; i++) {
      x[i] = ax;
      y[i] = ay + i * seg;
      _w[i] = i == 0 ? 0 : 1 / mass;
    }
  }

  final int n;
  final double ax, ay, length, seg;
  final Float64List x, y, vx, vy, _px, _py, _w;
}

class BadgeCard {
  BadgeCard(this.w, this.h, this.slot)
    : _inverseInertia = 1 / ((w * w + h * h) / 12),
      _ry = -h / 2 + slot;

  final double w, h, slot, _inverseInertia, _ry;
  static const double _rx = 0;
  static const double _inverseMass = 1;

  double x = 0, y = 0, a = 0;
  double vx = 0, vy = 0, va = 0;
  double _px = 0, _py = 0, _pa = 0;
  double _pvx = 0, _pvy = 0, _pva = 0;
  double yaw = 0, yawRate = 0, yawTarget = 0;
  double pitch = 0, pitchRate = 0, lift = 0;
  bool ceilingArmed = true;

  (double, double) slotOffset() {
    final c = math.cos(a), s = math.sin(a);
    return (c * _rx - s * _ry, s * _rx + c * _ry);
  }

  (double, double) slotWorld() {
    final (ox, oy) = slotOffset();
    return (x + ox, y + oy);
  }

  (double, double) toLocal(double px, double py) {
    final c = math.cos(a), s = math.sin(a);
    final dx = px - x, dy = py - y;
    return (c * dx + s * dy, -s * dx + c * dy);
  }

  (double, double) toWorld(double lx, double ly) {
    final c = math.cos(a), s = math.sin(a);
    return (x + c * lx - s * ly, y + s * lx + c * ly);
  }

  double halfWidth() => (w / 2) * math.max(math.cos(yaw).abs(), 0.3);
}

class Badge {
  Badge(this.id, this.strap, this.card);

  final String id;
  final BadgeStrap strap;
  final BadgeCard card;
  double hold = 0;
  double _kickPending = 0;
  double? _introT;
}

class _Grab {
  _Grab(this.badge, this.lx, this.ly, double x, double y)
    : tx = x,
      ty = y,
      cx = x,
      cy = y;

  final Badge badge;
  final double lx, ly;
  double tx, ty, cx, cy;
}

enum BadgeEventKind { card, wall, strap }

typedef BadgeEvent = ({BadgeEventKind kind, double speed, double t});
typedef _Contact = ({
  BadgeCard a,
  BadgeCard? b,
  double nx,
  double ny,
  double rAx,
  double rAy,
  double rBx,
  double rBy,
  double vnPre,
  double e,
  double mu,
  BadgeEventKind kind,
});

class BadgeWorld {
  BadgeWorld([this.cfg = const BadgePhysicsConfig()]);

  final BadgePhysicsConfig cfg;
  final badges = <Badge>[];
  final double g = 6278;
  double gx = 0, gy = 6278, gz = 0, az = 0;
  double yawRateDev = 0, pitchRateDev = 0;
  var walls = (left: 0.0, right: 1e9, top: -1e9, bottom: 1e9);
  _Grab? _grab;
  bool get isGrabbing => _grab != null;
  final _contacts = <_Contact>[];
  var _events = <BadgeEvent>[];
  double _acc = 0;
  double time = 0, calmFor = 0;

  Badge addBadge(
    String id,
    double anchorX,
    double anchorY,
    double strapLength,
    double cardW,
    double cardH,
    double slot,
  ) {
    final strap = BadgeStrap(
      anchorX,
      anchorY,
      strapLength,
      cfg.strapSegments,
      cfg.strapParticleMass,
    );
    final card = BadgeCard(cardW, cardH, slot);
    final b = Badge(id, strap, card);
    badges.add(b);
    placeAtRest(b);
    return b;
  }

  void placeAtRest(Badge b, [double dirx = 0, double diry = 1]) {
    final st = b.strap, c = b.card;
    final distance = _hypot(dirx, diry);
    final len = distance == 0 ? 1 : distance;
    final ux = dirx / len, uy = diry / len;
    for (var i = 0; i <= st.n; i++) {
      st.x[i] = st.ax + ux * st.seg * i;
      st.y[i] = st.ay + uy * st.seg * i;
      st.vx[i] = st.vy[i] = 0;
    }
    final sx = st.x[st.n], sy = st.y[st.n];
    c.a = math.atan2(-ux, uy);
    final d = c.h / 2 - c.slot;
    c.x = sx + ux * d;
    c.y = sy + uy * d;
    c.vx = c.vy = c.va = 0;
    c.yaw = c.yawTarget;
    c.yawRate = 0;
    c.pitch = 0;
    c.pitchRate = 0;
  }

  void placeForDrop(
    Badge b,
    double offsetX,
    double dropRatio,
    double delay, [
    double yawKick = 0,
  ]) {
    final st = b.strap, c = b.card;
    final sx = st.ax + offsetX, sy = st.ay + st.length * dropRatio;
    for (var i = 0; i <= st.n; i++) {
      final t = i / st.n;
      final bulge =
          math.sin(t * math.pi) * st.length * 0.12 * (offsetX >= 0 ? -1 : 1);
      st.x[i] = st.ax + (sx - st.ax) * t + bulge;
      st.y[i] = st.ay + (sy - st.ay) * t;
      st.vx[i] = st.vy[i] = 0;
    }
    c.a = offsetX * -0.002;
    final (ox, oy) = c.slotOffset();
    c.x = sx - ox;
    c.y = sy - oy;
    c.vx = c.vy = c.va = 0;
    c.yawTarget = 0;
    c.yaw = 0;
    c.yawRate = 0;
    c.pitch = 0;
    c.pitchRate = 0;
    c.ceilingArmed = false;
    b.hold = delay;
    b._kickPending = yawKick;
    b._introT = -delay;
  }

  void setWalls(double left, double right, double top, double bottom) {
    walls = (left: left, right: right, top: top, bottom: bottom);
  }

  void setGravity(double gx, double gy, double gz, [double az = 0]) {
    this.gx = gx;
    this.gy = gy;
    this.gz = gz;
    this.az = az;
  }

  void setRotationRates(double yawRate, double pitchRate) {
    yawRateDev = yawRate;
    pitchRateDev = pitchRate;
  }

  Badge? find(String id) {
    for (final b in badges) {
      if (b.id == id) return b;
    }
    return null;
  }

  void startGrab(String id, double x, double y) {
    final b = find(id);
    if (b == null) return;
    final (lx, ly) = b.card.toLocal(x, y);
    _grab = _Grab(b, lx, ly, x, y);
    calmFor = 0;
  }

  void moveGrab(double x, double y) {
    final grab = _grab;
    if (grab == null) return;
    grab.tx = x;
    grab.ty = y;
    calmFor = 0;
  }

  void endGrab() {
    _grab = null;
  }

  void flip(String id, [double dir = 1]) {
    final b = find(id);
    if (b == null) return;
    final c = b.card;
    final s = dir == 0 ? 1 : dir;
    if (c.yawTarget == 0) {
      c.yawTarget = math.pi * s;
      c.yawRate += cfg.flipKick * s;
    } else {
      final back = c.yaw > 0 ? -1 : 1;
      c.yawTarget = 0;
      c.yawRate += cfg.flipKick * back;
    }
    calmFor = 0;
  }

  void tug(String id, [double strength = 1]) {
    final b = find(id);
    if (b == null) return;
    final k = strength == 0 ? 1 : strength;
    b.card.vy -= 900 * k;
    b.card.va += 1.6 * k * (_random.nextBool() ? -1 : 1);
    b.card.yawRate += 3 * k;
    calmFor = 0;
  }

  static final _random = math.Random();

  void impulse(double vx, double vy) {
    for (final b in badges) {
      b.card.vx += vx;
      b.card.vy += vy;
      final st = b.strap;
      for (var i = 1; i <= st.n; i++) {
        st.vx[i] += vx * (i / st.n);
        st.vy[i] += vy * (i / st.n);
      }
    }
    calmFor = 0;
  }

  int step(double dt) {
    dt = math.min(dt, 1 / 20);
    _acc += dt;
    var steps = 0;
    while (_acc >= badgeSubstep && steps < 40) {
      _substep(badgeSubstep);
      _acc -= badgeSubstep;
      steps++;
    }
    if (steps == 40) _acc = 0;
    time += dt;
    calmFor = speed() < cfg.calmSpeed && _grab == null ? calmFor + dt : 0;
    return steps;
  }

  void _substep(double h) {
    final grab = _grab;
    if (grab != null) {
      grab.cx += (grab.tx - grab.cx) * 0.35;
      grab.cy += (grab.ty - grab.cy) * 0.35;
    }
    final press = math.min(gz.abs() / g, 1);
    final dStrap = math.exp(-cfg.strapDrag * h);
    final dCard = math.exp(-(cfg.cardDrag + cfg.pressFriction * press) * h);
    final dAng = math.exp(
      -(cfg.cardAngularDrag + cfg.pressFriction * press) * h,
    );

    for (final b in badges) {
      final st = b.strap, c = b.card;
      if (b.hold > 0) {
        b.hold -= h;
        continue;
      }
      final introT = b._introT;
      if (introT != null) b._introT = introT + h;
      for (var i = 1; i <= st.n; i++) {
        st.vx[i] = st.vx[i] * dStrap + gx * h;
        st.vy[i] = st.vy[i] * dStrap + gy * h;
        st._px[i] = st.x[i];
        st._py[i] = st.y[i];
        st.x[i] += st.vx[i] * h;
        st.y[i] += st.vy[i] * h;
      }
      final slow = math.max(0, 1 - _hypot(c.vx, c.vy) / cfg.settleSpeed);
      final dSettle = slow > 0
          ? math.exp(-cfg.settleDrag * slow * slow * h)
          : 1;
      c.vx = c.vx * dCard * dSettle + gx * h;
      c.vy = c.vy * dCard * dSettle + gy * h;
      c.va *= dAng * dSettle;
      c._pvx = c.vx;
      c._pvy = c.vy;
      c._pva = c.va;
      c._px = c.x;
      c._py = c.y;
      c._pa = c.a;
      c.x += c.vx * h;
      c.y += c.vy * h;
      c.a += c.va * h;
    }

    // One Gauss-Seidel pass. Rope length has priority over the other constraints.
    _contacts.clear();
    if (grab != null && grab.badge.hold <= 0) _solveGrab(grab);
    for (final b in badges) {
      if (b.hold > 0) continue;
      final st = b.strap;
      for (var i = 0; i < st.n; i++) {
        _solveDist(st, i, i + 1, st.seg, 1);
      }
      for (var i = 0; i < st.n - 1; i++) {
        _solveDist(st, i, i + 2, st.seg * 2, cfg.bendStiffness);
      }
      _solveAttach(st, st.n, b.card);
    }
    for (var i = 0; i < badges.length; i++) {
      for (var j = i + 1; j < badges.length; j++) {
        final a = badges[i], b = badges[j];
        if (a.hold > 0 || b.hold > 0) continue;
        _collideCards(a.card, b.card);
      }
    }
    for (final b in badges) {
      if (b.hold > 0) continue;
      _collideWalls(b.card);
      _limitLength(b);
    }

    for (final b in badges) {
      if (b.hold > 0) continue;
      final st = b.strap;
      for (var i = 1; i <= st.n; i++) {
        st.vx[i] = (st.x[i] - st._px[i]) / h;
        st.vy[i] = (st.y[i] - st._py[i]) / h;
      }
      final c = b.card;
      c.vx = (c.x - c._px) / h;
      c.vy = (c.y - c._py) / h;
      c.va = (c.a - c._pa) / h;
    }
    _solveVelocities();
    for (final b in badges) {
      final c = b.card;
      final sp = _hypot(c.vx, c.vy);
      if (sp > cfg.maxSpeed) {
        c.vx *= cfg.maxSpeed / sp;
        c.vy *= cfg.maxSpeed / sp;
      }
      c.va = c.va.clamp(-cfg.maxSpin, cfg.maxSpin);
    }

    final wy = 2 * math.pi * cfg.yawFreq;
    final ky = wy * wy;
    final cy = 2 * cfg.yawDamping * wy;
    final wp = 2 * math.pi * cfg.pitchFreq;
    final kp = wp * wp;
    final cp = 2 * cfg.pitchDamping * wp;
    final gAll = math.sqrt(gx * gx + gy * gy + gz * gz);
    final leanExponent = math.exp(2 * ((1.3 * gz) / (gAll == 0 ? 1 : gAll)));
    final leanTarget = cfg.pitchLean * (leanExponent - 1) / (leanExponent + 1);
    for (final b in badges) {
      final c = b.card;
      if (b.hold > 0) continue;
      final grabbed = grab?.badge == b;
      final rel = c.yaw - c.yawTarget;
      final introT = b._introT;
      final intro = introT != null && introT < 2.2
          ? cfg.introDamping +
                (1 - cfg.introDamping) * math.max(introT, 0) / 2.2
          : 1;
      var ty = -ky * rel - cy * intro * (c.yawRate - yawRateDev);
      ty += cfg.broadside * (c.vx * c.vx + c.vy * c.vy) * math.sin(2 * c.yaw);
      c.yawRate += ty * h;
      c.yaw += (c.yawRate - yawRateDev) * h;

      final pTarget = leanTarget + (grabbed ? cfg.liftPitch : 0);
      final tp =
          -kp * (c.pitch - pTarget) - cp * c.pitchRate + cfg.pitchShake * az;
      c.pitchRate += tp * h;
      c.pitch += (c.pitchRate - pitchRateDev * cfg.pitchInertia) * h;
      if (c.pitch > cfg.pitchMax) {
        c.pitch = cfg.pitchMax;
        if (c.pitchRate > 0) c.pitchRate *= -0.3;
      } else if (c.pitch < -cfg.pitchMax) {
        c.pitch = -cfg.pitchMax;
        if (c.pitchRate < 0) c.pitchRate *= -0.3;
      }
      c.lift += ((grabbed ? 1 : 0) - c.lift) * (1 - math.exp(-h * 14));
    }
  }

  void _solveDist(BadgeStrap st, int i, int j, double rest, double k) {
    final dx = st.x[j] - st.x[i], dy = st.y[j] - st.y[i];
    final len = _hypot(dx, dy);
    if (len < 1e-9) return;
    final wi = st._w[i], wj = st._w[j];
    final ws = wi + wj;
    if (ws == 0) return;
    final s = (k * (len - rest)) / (len * ws);
    st.x[i] += wi * s * dx;
    st.y[i] += wi * s * dy;
    st.x[j] -= wj * s * dx;
    st.y[j] -= wj * s * dy;
  }

  void _solveAttach(BadgeStrap st, int i, BadgeCard c) {
    final (rwx, rwy) = c.slotOffset();
    final dx = c.x + rwx - st.x[i], dy = c.y + rwy - st.y[i];
    final distance = _hypot(dx, dy);
    if (distance < 1e-9) return;
    final nx = dx / distance, ny = dy / distance;
    final rn = _cross(rwx, rwy, nx, ny);
    final wp = st._w[i];
    final wb = BadgeCard._inverseMass + rn * rn * c._inverseInertia;
    final lam = distance / (wp + wb);
    st.x[i] += wp * lam * nx;
    st.y[i] += wp * lam * ny;
    c.x -= BadgeCard._inverseMass * lam * nx;
    c.y -= BadgeCard._inverseMass * lam * ny;
    c.a -= c._inverseInertia * lam * rn;
  }

  void _limitLength(Badge b) {
    final st = b.strap;
    for (var i = 2; i <= st.n; i++) {
      final dx = st.x[i] - st.ax, dy = st.y[i] - st.ay;
      final d = _hypot(dx, dy);
      final max = st.seg * i;
      if (d > max) {
        st.x[i] = st.ax + (dx / d) * max;
        st.y[i] = st.ay + (dy / d) * max;
      }
    }
    final c = b.card;
    final (rwx, rwy) = c.slotOffset();
    final qx = c.x + rwx, qy = c.y + rwy;
    final dx = st.ax - qx, dy = st.ay - qy;
    final d = _hypot(dx, dy);
    if (b._kickPending != 0 && d > st.length * 0.96) {
      c.yawRate += b._kickPending;
      b._kickPending = 0;
    }
    final correction = d - st.length * 1.002;
    if (correction <= 0) return;
    final nx = dx / d, ny = dy / d;
    final rn = _cross(rwx, rwy, nx, ny);
    final vnPre = (c._pvx - c._pva * rwy) * nx + (c._pvy + c._pva * rwx) * ny;
    _contacts.add((
      a: c,
      b: null,
      nx: nx,
      ny: ny,
      rAx: rwx,
      rAy: rwy,
      rBx: 0,
      rBy: 0,
      vnPre: vnPre,
      e: cfg.restitutionStrap,
      mu: 0,
      kind: BadgeEventKind.strap,
    ));
    final w = BadgeCard._inverseMass + rn * rn * c._inverseInertia;
    final lam = correction / w;
    c.x += BadgeCard._inverseMass * lam * nx;
    c.y += BadgeCard._inverseMass * lam * ny;
    c.a += c._inverseInertia * lam * rn;
    // Translation removes any stretch left by the linearized rotation.
    final (r2x, r2y) = c.slotOffset();
    final ex = st.ax - (c.x + r2x), ey = st.ay - (c.y + r2y);
    final e = _hypot(ex, ey);
    final over = e - st.length * 1.002;
    if (over > 0) {
      c.x += (ex / e) * over;
      c.y += (ey / e) * over;
    }
  }

  void _solveGrab(_Grab g) {
    final c = g.badge.card;
    final (gx, gy) = c.toWorld(g.lx, g.ly);
    final dx = g.cx - gx, dy = g.cy - gy;
    final distance = _hypot(dx, dy);
    if (distance < 1e-9) return;
    final nx = dx / distance, ny = dy / distance;
    final rx = gx - c.x, ry = gy - c.y;
    final rn = _cross(rx, ry, nx, ny);
    final w = BadgeCard._inverseMass + rn * rn * c._inverseInertia;
    final lam = math.min(cfg.grabStiffness * distance, cfg.grabMaxMove) / w;
    c.x += BadgeCard._inverseMass * lam * nx;
    c.y += BadgeCard._inverseMass * lam * ny;
    c.a += c._inverseInertia * lam * rn;
  }

  List<(double, double)> corners(BadgeCard c, double inset) {
    final hw = c.halfWidth() - inset, hh = c.h / 2 - inset;
    return [
      c.toWorld(-hw, -hh),
      c.toWorld(hw, -hh),
      c.toWorld(hw, hh),
      c.toWorld(-hw, hh),
    ];
  }

  // Push the deepest corner through its nearest edge.
  void _collideCards(BadgeCard a, BadgeCard b) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final reach = (_hypot(a.w, a.h) + _hypot(b.w, b.h)) / 2;
    if (dx * dx + dy * dy > reach * reach) return;
    (BadgeCard, BadgeCard, double, double, double, double, double)? best;
    void test(BadgeCard p, BadgeCard q) {
      final hw = q.halfWidth(), hh = q.h / 2;
      for (final (wx, wy) in corners(p, 3)) {
        final (lx, ly) = q.toLocal(wx, wy);
        final px = hw - lx.abs(), py = hh - ly.abs();
        if (px <= 0 || py <= 0) continue;
        double nlx = 0, nly = 0;
        final double pen;
        if (px < py) {
          pen = px;
          nlx = lx >= 0 ? 1 : -1;
        } else {
          pen = py;
          nly = ly >= 0 ? 1 : -1;
        }
        final previous = best;
        if (previous == null || pen > previous.$7) {
          final cq = math.cos(q.a), sq = math.sin(q.a);
          final nx = cq * nlx - sq * nly;
          final ny = sq * nlx + cq * nly;
          best = (p, q, wx, wy, nx, ny, pen);
        }
      }
    }

    test(a, b);
    test(b, a);
    final hit = best;
    if (hit == null) return;
    final (p, q, wx, wy, nx, ny, pen) = hit;
    final rPx = wx - p.x, rPy = wy - p.y;
    final rQx = wx - q.x, rQy = wy - q.y;
    final rnP = _cross(rPx, rPy, nx, ny);
    final rnQ = _cross(rQx, rQy, nx, ny);
    final wP = BadgeCard._inverseMass + rnP * rnP * p._inverseInertia;
    final wQ = BadgeCard._inverseMass + rnQ * rnQ * q._inverseInertia;
    final lam = math.min(pen, cfg.maxPush) / (wP + wQ);
    p.x += BadgeCard._inverseMass * lam * nx;
    p.y += BadgeCard._inverseMass * lam * ny;
    p.a += p._inverseInertia * lam * rnP;
    q.x -= BadgeCard._inverseMass * lam * nx;
    q.y -= BadgeCard._inverseMass * lam * ny;
    q.a -= q._inverseInertia * lam * rnQ;
    final vPx = p._pvx - p._pva * rPy, vPy = p._pvy + p._pva * rPx;
    final vQx = q._pvx - q._pva * rQy, vQy = q._pvy + q._pva * rQx;
    final vnPre = (vPx - vQx) * nx + (vPy - vQy) * ny;
    _contacts.add((
      a: p,
      b: q,
      nx: nx,
      ny: ny,
      rAx: rPx,
      rAy: rPy,
      rBx: rQx,
      rBy: rQy,
      vnPre: vnPre,
      e: cfg.restitutionCard,
      mu: cfg.frictionCard,
      kind: BadgeEventKind.card,
    ));
  }

  void _collideWalls(BadgeCard c) {
    final w = walls;
    (double, double, double, double, double)? best;
    final pts = corners(c, 4);
    if (!c.ceilingArmed && pts.every((point) => point.$2 > w.top + 1)) {
      c.ceilingArmed = true;
    }
    final top = c.ceilingArmed ? w.top : -1e9;
    for (final (wx, wy) in pts) {
      final tests = <(double, double, double)>[
        (w.left - wx, 1, 0),
        (wx - w.right, -1, 0),
        (top - wy, 0, 1),
        (wy - w.bottom, 0, -1),
      ];
      for (final (pen, nx, ny) in tests) {
        if (pen > 0 && (best == null || pen > best.$5)) {
          best = (wx, wy, nx, ny, pen);
        }
      }
    }
    if (best == null) return;
    final (wx, wy, nx, ny, pen) = best;
    final rx = wx - c.x, ry = wy - c.y;
    final rn = _cross(rx, ry, nx, ny);
    final effectiveMass = BadgeCard._inverseMass + rn * rn * c._inverseInertia;
    final lam = math.min(pen, cfg.maxPush) / effectiveMass;
    c.x += BadgeCard._inverseMass * lam * nx;
    c.y += BadgeCard._inverseMass * lam * ny;
    c.a += c._inverseInertia * lam * rn;
    final vnPre = (c._pvx - c._pva * ry) * nx + (c._pvy + c._pva * rx) * ny;
    _contacts.add((
      a: c,
      b: null,
      nx: nx,
      ny: ny,
      rAx: rx,
      rAy: ry,
      rBx: 0,
      rBy: 0,
      vnPre: vnPre,
      e: cfg.restitutionWall,
      mu: cfg.frictionWall,
      kind: BadgeEventKind.wall,
    ));
  }

  void _solveVelocities() {
    for (final k in _contacts) {
      final a = k.a, b = k.b;
      final vAx = a.vx - a.va * k.rAy;
      final vAy = a.vy + a.va * k.rAx;
      final vBx = b == null ? 0 : b.vx - b.va * k.rBy;
      final vBy = b == null ? 0 : b.vy + b.va * k.rBx;
      final rvx = vAx - vBx, rvy = vAy - vBy;
      final vn = rvx * k.nx + rvy * k.ny;
      final rnA = _cross(k.rAx, k.rAy, k.nx, k.ny);
      final rnB = b == null ? 0.0 : _cross(k.rBx, k.rBy, k.nx, k.ny);
      final wA = BadgeCard._inverseMass + rnA * rnA * a._inverseInertia;
      final wB = b == null
          ? 0
          : BadgeCard._inverseMass + rnB * rnB * b._inverseInertia;
      final target = k.vnPre < -60 ? -k.e * k.vnPre : 0;
      final dv = target - vn;
      if (dv > 0) {
        final j = dv / (wA + wB);
        a.vx += BadgeCard._inverseMass * j * k.nx;
        a.vy += BadgeCard._inverseMass * j * k.ny;
        a.va += a._inverseInertia * j * rnA;
        if (b != null) {
          b.vx -= BadgeCard._inverseMass * j * k.nx;
          b.vy -= BadgeCard._inverseMass * j * k.ny;
          b.va -= b._inverseInertia * j * rnB;
        }
      }

      final tx = -k.ny, ty = k.nx;
      final vt = rvx * tx + rvy * ty;
      final rtA = _cross(k.rAx, k.rAy, tx, ty);
      final rtB = b == null ? 0.0 : _cross(k.rBx, k.rBy, tx, ty);
      final wtA = BadgeCard._inverseMass + rtA * rtA * a._inverseInertia;
      final wtB = b == null
          ? 0
          : BadgeCard._inverseMass + rtB * rtB * b._inverseInertia;
      final jt = (-vt * k.mu) / (wtA + wtB);
      a.vx += BadgeCard._inverseMass * jt * tx;
      a.vy += BadgeCard._inverseMass * jt * ty;
      a.va += a._inverseInertia * jt * rtA;
      if (b != null) {
        b.vx -= BadgeCard._inverseMass * jt * tx;
        b.vy -= BadgeCard._inverseMass * jt * ty;
        b.va -= b._inverseInertia * jt * rtB;
      }
      if (k.vnPre < -cfg.hitEventSpeed) {
        _events.add((kind: k.kind, speed: -k.vnPre, t: time));
      }
    }
  }

  double speed() {
    var sum = 0.0, n = 0;
    for (final b in badges) {
      final c = b.card;
      final r = c.h / 2;
      sum += c.vx * c.vx + c.vy * c.vy;
      sum += c.va * r * (c.va * r);
      final yr = (c.yawRate - yawRateDev) * r;
      sum += yr * yr;
      sum += c.pitchRate * r * (c.pitchRate * r);
      final yawErr = (c.yaw - c.yawTarget) * r;
      sum += yawErr * yawErr * 4;
      n += 4;
      if (b.hold > 0) sum += 1e6;
    }
    if (_grab != null) sum += 1e6;
    return math.sqrt(sum / math.max(n, 1));
  }

  List<BadgeEvent> takeEvents() {
    final e = _events;
    _events = [];
    return e;
  }
}

typedef _Vector3 = ({double x, double y, double z});

/// Card normal and tangents in screen coordinates.
({_Vector3 n, _Vector3 tx, _Vector3 ty}) cardBasis(
  double a,
  double pitch,
  double yaw,
) {
  final cy = math.cos(yaw), sy = math.sin(yaw);
  final cp = math.cos(pitch), sp = math.sin(pitch);
  final ca = math.cos(a), sa = math.sin(a);
  _Vector3 rz(double x, double y, double z) =>
      (x: x * ca - y * sa, y: x * sa + y * ca, z: z);
  return (
    n: rz(sy, -cy * sp, cy * cp),
    tx: rz(cy, sy * sp, -sy * cp),
    ty: rz(0, cp, sp),
  );
}
