import 'package:chh_app/core/md5.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vectors = {
    '': 'd41d8cd98f00b204e9800998ecf8427e',
    'a': '0cc175b9c0f1b6a831c399e269772661',
    'abc': '900150983cd24fb0d6963f7d28e17f72',
    'message digest': 'f96b697d7cb7938d525a2f31aaf161d0',
    'abcdefghijklmnopqrstuvwxyz': 'c3fcd3d76192e4007dfb496cca67e13b',
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789':
        'd174ab98d277d9f5a5611c2c9f419d9f',
    '12345678901234567890123456789012345678901234567890123456789012345678901234567890':
        '57edf4a22be3c955ac49da2e2107b67a',
    '中文密码': '3d4acf94adca8562b4990599b15488de',
    '密码🔒': 'f724f4a16842d22d811c7fe33bb71105',
  };
  for (final entry in vectors.entries) {
    test('MD5 UTF-8 vector: ${entry.key}', () {
      expect(md5(entry.key), entry.value);
    });
  }
  test('MD5 processes many blocks', () {
    expect(md5('a' * 1000000), '7707d6ae4e027c70eea2a935c2296f21');
  });
}
