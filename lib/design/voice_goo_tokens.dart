/// Numeric parameters from the prototype's goo geometry and Composer springs.
/// Kept free of Flutter imports so that the simulation can run on the Dart VM.
abstract final class VoiceGooTokens {
  static const breakDistance = 110.0;
  static const rejoinDistance = 78.0;
  static const fingerOffset = 28.0;
  static const pullBonusLimit = 24.0;
  static const pullBonus = .5;
  static const neckMinDistance = 14.0;
  static const neckVisibleDistance = .5;
  static const retractContactDistance = 1.5;
  static const retractReleaseDistance = 4.0;
  static const retractTarget = 4.0;
  static const flatMargin = 4.0;
  static const flatFade = 28.0;
  static const trembleStart = .82;
  static const trembleAmplitude = 1.2;
  static const trembleFrequency = 72.0;
  static const anchorInset = 70.0;
  static const anchorLockLift = 6.0;
  static const anchorReleaseLift = 2.0;
  static const maxFootScale = 1.4;
  static const blobEdgeInset = 50.0;
  static const blobRadius = 19.0;
  static const neckRadiusBase = 6.0;
  static const neckRadiusGain = .13;
  static const neckRadiusDecay = 8.0;
  static const attachedSpring = (k: 420.0, c: 25.0);
  static const retractSpring = (k: 700.0, c: 40.0);
  static const zipSpring = (k: 300.0, c: 26.0);
  static const blobSpring = (k: 380.0, c: 24.0);
  static const scaleSpring = (k: 300.0, c: 14.0);
  static const tailSpring = (k: 420.0, c: 30.0);
  static const labelSpring = (k: 260.0, c: 22.0);
  static const shapeModes = [
    (k: 160.0, c: 9.0),
    (k: 260.0, c: 9.5),
    (k: 520.0, c: 13.0),
  ];
  static const tear = [.42, .25, .085];
  static const blobPoints = 40;
  static const minBlobRadius = 2.0;
  static const snapVelocity = 110.0;
  static const snapTear = .9;
  static const snapScale = .94;
  static const tailInitial = 15.0;
  static const tailStep = 1 / 120;
  static const tailWidth = 11.0;
  static const approachDistance = 36.0;
  static const approachHeight = 10.0;
  static const approachWidth = 16.0;
  static const redRadius = 480.0;
  static const redSpeed = 9.0;
  static const redRetreatSpeed = 12.0;
  static const redStroke = 1.2;
  static const gulpImpulse = 1.15;
  static const splashCount = 6;
  static const splashLife = .42;
  static const splashGravity = 640.0;
  static const popCount = 11;
  static const popLife = .46;
  static const popGravity = 160.0;
  static const popDrag = 3.2;
  static const ringLife = .42;
  static const labelFade = .15;
  static const labelWidth = 91.5;
  static const labelEdgeInset = 10.0;
  static const labelAbove = 50.0;
  static const labelBelow = 14.0;
  static const labelScreenTop = 52.0;
}
