/// 更新服务的网络层:签名验证、多地址回退、断点续传
///
/// 每个 JSON 响应都先用内置公钥验签再解析,所以走明文 HTTP 也不会被篡改地址或版本信息;
/// 安装包本身另有 sha256 与签名证书两道核对。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../core/app_log.dart';
import 'update_endpoints.dart';
import 'update_models.dart';
import 'update_platform.dart';

enum UpdateFailure {
  notConfigured,
  network,
  untrusted,
  busy,
  notFound,
  integrity,
  signer,
  install,
  storage,
  cancelled,
}

class UpdateException implements Exception {
  final UpdateFailure kind;
  final String? detail;
  const UpdateException(this.kind, [this.detail]);
  @override
  String toString() =>
      'UpdateException($kind${detail == null ? '' : ', $detail'})';
}

typedef DownloadProgress = void Function(int received, int total);

class UpdateClient {
  final Dio _dio;
  final UpdatePlatform platform;
  final Map<String, String> publicKeys;

  /// 断线后最多连续重试几次;每次都从已下载的位置续传
  final int maxRetries;
  final Duration retryDelay;

  UpdateClient({
    Dio? dio,
    required this.platform,
    this.publicKeys = updatePublicKeys,
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 2),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               // 两段数据之间的最长间隔,不是整个下载的时限
               receiveTimeout: const Duration(seconds: 30),
               headers: {'user-agent': 'chher-update'},
             ),
           );

  /// 检查版本接口;返回实际应答的地址,后续请求优先用它
  Future<(String, UpdateCheck)> check(
    List<String> endpoints, {
    required int versionCode,
    required String abi,
    required String installId,
  }) async {
    final query = Uri(
      queryParameters: {'vc': '$versionCode', 'abi': abi, 'did': installId},
    ).query;
    final (endpoint, payload) = await _signedGet(endpoints, '/v1/check?$query');
    return (endpoint, _parse(() => UpdateCheck.fromJson(payload)));
  }

  /// 更新信息接口:版本说明 + 限时下载链接
  Future<UpdateRelease> release(
    List<String> endpoints, {
    required int versionCode,
    required String abi,
  }) async {
    final query = Uri(queryParameters: {'abi': abi}).query;
    final (endpoint, payload) = await _signedGet(
      endpoints,
      '/v1/releases/$versionCode?$query',
    );
    return _parse(() => UpdateRelease.fromJson(payload, endpoint: endpoint));
  }

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on UpdateFormatException catch (error) {
      throw UpdateException(UpdateFailure.untrusted, error.field);
    }
  }

  /// 按顺序尝试每个地址;网络错误、繁忙和验签失败都换下一个地址
  Future<(String, Map<String, dynamic>)> _signedGet(
    List<String> endpoints,
    String pathAndQuery,
  ) async {
    if (endpoints.isEmpty) {
      throw const UpdateException(UpdateFailure.notConfigured);
    }
    UpdateException? last;
    for (final base in endpoints) {
      try {
        final response = await _dio.get<String>(
          '$base$pathAndQuery',
          options: Options(
            responseType: ResponseType.plain,
            validateStatus: (_) => true,
          ),
        );
        final status = response.statusCode ?? 0;
        if (status == 200) {
          return (base, await _verify(response.data ?? ''));
        }
        last = UpdateException(switch (status) {
          404 => UpdateFailure.notFound,
          429 || 503 => UpdateFailure.busy,
          _ => UpdateFailure.network,
        }, 'http $status');
      } on UpdateException catch (error) {
        last = error;
        AppLog.w('UPDATE', '$base 响应未通过验签');
      } on DioException catch (error) {
        last = UpdateException(UpdateFailure.network, error.type.name);
      }
    }
    throw last ?? const UpdateException(UpdateFailure.network);
  }

  Future<Map<String, dynamic>> _verify(String body) async {
    try {
      final envelope = jsonDecode(body) as Map<String, dynamic>;
      final key = publicKeys[envelope['kid']];
      if (key == null) throw const FormatException('kid');
      final payload = base64Decode(envelope['payload'] as String);
      final signature = base64Decode(envelope['sig'] as String);
      final ok = await platform.verifySignature(
        base64Decode(key),
        payload,
        signature,
      );
      if (!ok) throw const FormatException('signature');
      return jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } on UpdateException {
      rethrow;
    } catch (error) {
      throw UpdateException(UpdateFailure.untrusted, '$error');
    }
  }

  /// 下载到 [dir];已下载的部分用 Range + If-Range 续传,换了版本的残片会被丢弃。
  /// 链接过期时调用 [refreshLink] 换一条新链接继续。
  Future<File> download(
    UpdateRelease release,
    Directory dir, {
    required DownloadProgress onProgress,
    required Future<UpdateRelease> Function() refreshLink,
    CancelToken? cancel,
  }) async {
    final apk = File('${dir.path}/chher-${release.versionCode}.apk');
    final part = File('${apk.path}.part');
    final marker = File('${apk.path}.part.sha256');
    try {
      await dir.create(recursive: true);
      if (await apk.exists() && await apk.length() == release.size) {
        onProgress(release.size, release.size);
        return apk;
      }
      var offset = 0;
      if (await part.exists() &&
          await marker.exists() &&
          (await marker.readAsString()) == release.sha256) {
        offset = await part.length();
      }
      if (offset == 0 || offset > release.size) {
        offset = 0;
        await part.writeAsBytes(const [], flush: true);
        await marker.writeAsString(release.sha256, flush: true);
      }
      onProgress(offset, release.size);

      var current = release;
      var relinked = false;
      var failures = 0;
      while (offset < release.size) {
        try {
          final response = await _dio.get<ResponseBody>(
            current.downloadUri.toString(),
            cancelToken: cancel,
            options: Options(
              responseType: ResponseType.stream,
              validateStatus: (_) => true,
              headers: offset == 0
                  ? null
                  : {
                      'range': 'bytes=$offset-',
                      // 服务器上的文件变了就整包重下,不拼接两个版本
                      'if-range': '"${release.sha256}"',
                    },
            ),
          );
          final status = response.statusCode ?? 0;
          if (status == 403 && !relinked) {
            relinked = true;
            await _drain(response);
            current = await refreshLink();
            continue;
          }
          if (status == 429 || status == 503) {
            await _drain(response);
            throw UpdateException(UpdateFailure.busy, 'http $status');
          }
          if (status == 404) {
            await _drain(response);
            throw const UpdateException(UpdateFailure.notFound);
          }
          if (status == 200) {
            offset = 0;
          } else if (status != 206 || !_rangeStartsAt(response, offset)) {
            await _drain(response);
            throw UpdateException(UpdateFailure.network, 'http $status');
          }
          final sink = part.openWrite(
            mode: offset == 0 ? FileMode.write : FileMode.append,
          );
          try {
            await for (final chunk in response.data!.stream) {
              offset += chunk.length;
              if (offset > release.size) {
                throw const UpdateException(UpdateFailure.integrity, 'size');
              }
              sink.add(chunk);
              onProgress(offset, release.size);
            }
          } finally {
            await sink.flush();
            await sink.close();
          }
          failures = 0;
        } on UpdateException {
          rethrow;
        } catch (error) {
          if (cancel?.isCancelled ?? false) {
            throw const UpdateException(UpdateFailure.cancelled);
          }
          failures++;
          AppLog.w('UPDATE', '下载中断 ${error.runtimeType},第 $failures 次');
          if (failures > maxRetries) {
            throw UpdateException(
              UpdateFailure.network,
              '${error.runtimeType}',
            );
          }
          await Future<void>.delayed(retryDelay * failures);
          offset = await part.exists() ? await part.length() : 0;
        }
      }
      await part.rename(apk.path);
      if (await marker.exists()) await marker.delete();
      return apk;
    } on FileSystemException catch (error) {
      throw UpdateException(UpdateFailure.storage, error.message);
    }
  }

  bool _rangeStartsAt(Response<ResponseBody> response, int offset) {
    final range = response.headers.value('content-range') ?? '';
    return range.startsWith('bytes $offset-');
  }

  Future<void> _drain(Response<ResponseBody> response) async {
    try {
      await response.data?.stream.drain<void>();
    } catch (_) {
      // 丢弃响应体时的错误不影响后续判断
    }
  }
}
