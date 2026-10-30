import 'package:chh_app/network/webview_trust.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const proceed = ServerTrustAuthResponseAction.PROCEED;
  const cancel = ServerTrustAuthResponseAction.CANCEL;
  const leaf = [1, 2, 3];

  Future<ServerTrustAuthResponseAction> evaluate(
    WebViewTrustVerifier verifier, {
    String host = 'www.chiphell.com',
    String? protocol = 'https',
    int? port = 443,
    bool isAndroid = true,
    int? error = 3,
    List<int>? der = leaf,
  }) => verifier.evaluate(
    host: host,
    protocol: protocol,
    port: port,
    isAndroid: isAndroid,
    sslErrorCode: error,
    leafDer: der,
  );

  test('仅 Android 上三个指定主机的 HTTPS 缺根错误可进入核验', () async {
    var calls = 0;
    final verifier = WebViewTrustVerifier(
      verifyPeer: (_) async {
        calls++;
        return leaf;
      },
    );
    for (final host in [
      'example.com',
      'www.chiphell.com.evil',
      'other.chiphell.com',
      '',
    ]) {
      expect(await evaluate(verifier, host: host), cancel);
    }
    expect(await evaluate(verifier, protocol: 'http'), cancel);
    expect(await evaluate(verifier, protocol: null), cancel);
    expect(await evaluate(verifier, port: 8443), cancel);
    expect(await evaluate(verifier, isAndroid: false), cancel);
    for (final error in [null, 0, 1, 2, 4, 5]) {
      expect(await evaluate(verifier, error: error), cancel);
    }
    expect(await evaluate(verifier, der: null), cancel);
    expect(await evaluate(verifier, der: []), cancel);
    expect(calls, 0);
    for (final host in [
      'www.chiphell.com',
      'chiphell.com',
      'static.chiphell.com',
    ]) {
      expect(await evaluate(verifier, host: host, port: null), proceed);
    }
    expect(calls, 3);
  });

  test('验证失败、异常和 DER 不同均拒绝，失败不缓存', () async {
    var calls = 0;
    final verifier = WebViewTrustVerifier(
      verifyPeer: (_) async {
        calls++;
        if (calls == 1) return null;
        if (calls == 2) throw StateError('CERTIFICATE_VERIFY_FAILED');
        if (calls == 3) return [1, 2, 4];
        return leaf;
      },
    );
    for (var i = 0; i < 3; i++) {
      expect(await evaluate(verifier), cancel);
    }
    expect(await evaluate(verifier), proceed);
    expect(calls, 4);
    expect(await evaluate(verifier), proceed);
    expect(calls, 4);
  });

  test('缓存按主机和叶子 DER 隔离，命中后仍检查全部规则', () async {
    var calls = 0;
    final verifier = WebViewTrustVerifier(
      verifyPeer: (_) async {
        calls++;
        return leaf;
      },
    );
    expect(await evaluate(verifier), proceed);
    expect(await evaluate(verifier), proceed);
    expect(calls, 1);
    expect(await evaluate(verifier, error: 1), cancel);
    expect(await evaluate(verifier, protocol: 'http'), cancel);
    expect(await evaluate(verifier, host: 'chiphell.com'), proceed);
    expect(calls, 2);
    expect(await evaluate(verifier, der: [1, 2, 4]), cancel);
    expect(calls, 3);
  });
}
