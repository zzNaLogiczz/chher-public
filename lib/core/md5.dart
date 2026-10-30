/// Discuz 密码帖 Cookie 使用 UTF-8 文本的 MD5 小写摘要。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

const _rotations = [
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  7,
  12,
  17,
  22,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  5,
  9,
  14,
  20,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  4,
  11,
  16,
  23,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
  6,
  10,
  15,
  21,
];

final _constants = List<int>.generate(
  64,
  (index) => (math.sin(index + 1).abs() * 0x100000000).floor(),
  growable: false,
);

String md5(String input) {
  final bytes = utf8.encode(input);
  final paddedLength = ((bytes.length + 9 + 63) ~/ 64) * 64;
  final data = ByteData(paddedLength);
  data.buffer.asUint8List().setAll(0, bytes);
  data.setUint8(bytes.length, 0x80);
  data.setUint64(paddedLength - 8, bytes.length * 8, Endian.little);

  var a0 = 0x67452301;
  var b0 = 0xefcdab89;
  var c0 = 0x98badcfe;
  var d0 = 0x10325476;
  for (var offset = 0; offset < paddedLength; offset += 64) {
    var a = a0;
    var b = b0;
    var c = c0;
    var d = d0;
    for (var index = 0; index < 64; index++) {
      final int f;
      final int word;
      if (index < 16) {
        f = (b & c) | (~b & d);
        word = index;
      } else if (index < 32) {
        f = (d & b) | (~d & c);
        word = (5 * index + 1) % 16;
      } else if (index < 48) {
        f = b ^ c ^ d;
        word = (3 * index + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        word = (7 * index) % 16;
      }
      final value =
          (a +
              f +
              _constants[index] +
              data.getUint32(offset + word * 4, Endian.little)) &
          0xffffffff;
      final shift = _rotations[index];
      final rotated =
          ((value << shift) | (value >>> (32 - shift))) & 0xffffffff;
      a = d;
      d = c;
      c = b;
      b = (b + rotated) & 0xffffffff;
    }
    a0 = (a0 + a) & 0xffffffff;
    b0 = (b0 + b) & 0xffffffff;
    c0 = (c0 + c) & 0xffffffff;
    d0 = (d0 + d) & 0xffffffff;
  }

  final digest = ByteData(16)
    ..setUint32(0, a0, Endian.little)
    ..setUint32(4, b0, Endian.little)
    ..setUint32(8, c0, Endian.little)
    ..setUint32(12, d0, Endian.little);
  return digest.buffer
      .asUint8List()
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}
