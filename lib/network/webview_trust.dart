import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'trusted_roots.dart';

/// 独立握手保留系统根、证书链及主机名校验，不发送 HTTP 请求。
Future<Uint8List?> verifyServerLeaf(String host) async {
  final socket = await io.SecureSocket.connect(
    host,
    443,
    context: buildTrustContext(),
    timeout: const Duration(seconds: 15),
  );
  try {
    return socket.peerCertificate?.der;
  } finally {
    socket.destroy();
  }
}

class WebViewTrustVerifier {
  WebViewTrustVerifier({Future<List<int>?> Function(String host)? verifyPeer})
    : _verifyPeer = verifyPeer ?? verifyServerLeaf;

  final Future<List<int>?> Function(String host) _verifyPeer;
  final _verified = <(String, String)>{};

  /// 规则与网络分离，只有 Android 缺根且两侧叶子一致才放行。
  Future<ServerTrustAuthResponseAction> evaluate({
    required String host,
    required String? protocol,
    required int? port,
    required bool isAndroid,
    required int? sslErrorCode,
    required List<int>? leafDer,
  }) async {
    const hosts = {'www.chiphell.com', 'chiphell.com', 'static.chiphell.com'};
    if (!isAndroid ||
        !hosts.contains(host) ||
        protocol != 'https' ||
        (port != null && port != 443) ||
        sslErrorCode != 3 ||
        leafDer == null ||
        leafDer.isEmpty) {
      return ServerTrustAuthResponseAction.CANCEL;
    }
    // 在异步握手前固定字节，避免调用方变更影响缓存与比较。
    final expected = Uint8List.fromList(leafDer);
    final key = (host, base64Encode(expected));
    if (_verified.contains(key)) return ServerTrustAuthResponseAction.PROCEED;
    try {
      final peer = await _verifyPeer(host);
      if (peer != null && listEquals(expected, peer)) {
        _verified.add(key);
        return ServerTrustAuthResponseAction.PROCEED;
      }
    } catch (_) {
      // 任何握手或证书错误均拒绝，失败不缓存。
    }
    return ServerTrustAuthResponseAction.CANCEL;
  }
}

final _webViewTrustVerifier = WebViewTrustVerifier();

Future<ServerTrustAuthResponse> handleServerTrustChallenge(
  URLAuthenticationChallenge challenge, {
  void Function(String reason)? onResult,
}) async {
  final space = challenge.protectionSpace;
  final action = await _webViewTrustVerifier.evaluate(
    host: space.host,
    protocol: space.protocol,
    port: space.port,
    isAndroid: io.Platform.isAndroid,
    sslErrorCode: space.sslError?.code?.toNativeValue(),
    leafDer: space.sslCertificate?.x509Certificate?.encoded,
  );
  onResult?.call('SSL $action: ${space.host}');
  return ServerTrustAuthResponse(action: action);
}
