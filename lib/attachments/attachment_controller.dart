/// 编辑器里的图片:选图 → 压缩 → 上传,逐张串行
///
/// 上传成功只代表站点收下了附件;要等正文提交时带上附件编号才归入帖子,
/// 所以这里只管"有哪些已上传的编号",正文拼接与提交字段在 PostRepository。
library;

import 'package:flutter/foundation.dart';

import 'dart:io';

import '../data/post_repository.dart';
import '../models/models.dart';
import '../parser/upload_parser.dart';
import 'image_pipeline.dart';

enum AttachmentState { waiting, preparing, uploading, done, failed }

class ComposeImage {
  final int id;
  final String uri;
  AttachmentState state = AttachmentState.waiting;

  /// 处理后的本地文件,同时用作缩略图
  String? path;
  String? aid;
  String? error;

  ComposeImage(this.id, this.uri);

  bool get pending =>
      state == AttachmentState.waiting ||
      state == AttachmentState.preparing ||
      state == AttachmentState.uploading;
}

typedef ImageUploader =
    Future<UploadOutcome> Function(UploadContext context, PreparedImage image);

/// 用发帖仓库上传处理好的图片
ImageUploader uploaderFor(PostRepository repo) =>
    (context, image) async => repo.uploadImage(
      context,
      bytes: await File(image.path).readAsBytes(),
      filename: image.filename,
      contentType: image.contentType,
    );

class AttachmentController extends ChangeNotifier {
  /// 取上传参数(来自发帖/回帖表单页);拿不到说明当前不能上传
  final Future<UploadContext?> Function() loadContext;
  final ImageUploader upload;
  final ImagePipeline pipeline;

  /// 单次发布最多带的图片数
  final int limit;

  AttachmentController({
    required this.loadContext,
    required this.upload,
    this.pipeline = const ImagePipeline(),
    this.limit = 9,
  });

  final _items = <ComposeImage>[];
  var _nextId = 0;
  UploadContext? _context;
  bool _running = false;
  bool _disposed = false;

  List<ComposeImage> get items => List.unmodifiable(_items);
  bool get busy => _items.any((i) => i.pending);
  bool get hasFailed => _items.any((i) => i.state == AttachmentState.failed);
  int get remaining => limit - _items.length;

  /// 已上传的附件编号,按选择顺序
  List<String> get aids => [
    for (final i in _items)
      if (i.state == AttachmentState.done) i.aid!,
  ];

  Future<void> pick() async {
    if (remaining <= 0) return;
    add(await pipeline.platform.pick(remaining));
  }

  void add(List<String> uris) {
    for (final uri in uris.take(remaining)) {
      _items.add(ComposeImage(_nextId++, uri));
    }
    _changed();
    _pump();
  }

  void retry(int id) {
    final item = _find(id);
    if (item == null || item.state != AttachmentState.failed) return;
    item
      ..state = AttachmentState.waiting
      ..error = null;
    _changed();
    _pump();
  }

  void remove(int id) {
    final item = _find(id);
    if (item == null) return;
    _items.remove(item);
    _discard(item);
    _changed();
  }

  ComposeImage? _find(int id) => _items.where((i) => i.id == id).firstOrNull;

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (!_disposed) {
        final next = _items
            .where((i) => i.state == AttachmentState.waiting)
            .firstOrNull;
        if (next == null) break;
        await _process(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _process(ComposeImage item) async {
    try {
      final context = _context ??= await loadContext();
      if (context == null) {
        return _fail(item, '当前无法上传图片，请确认已登录');
      }
      // 重试时已经压缩过的文件直接复用
      PreparedImage? prepared;
      if (item.path == null) {
        item.state = AttachmentState.preparing;
        _changed();
        prepared = await pipeline.prepare(
          item.uri,
          maxBytes: context.maxBytes,
          allowed: context.extensions,
        );
        if (!_items.contains(item)) {
          await pipeline.platform.discard(prepared.path);
          return;
        }
        item.path = prepared.path;
        _prepared[item.id] = prepared;
      } else {
        prepared = _prepared[item.id];
      }
      item.state = AttachmentState.uploading;
      _changed();
      final outcome = await upload(context, prepared!);
      // 上传途中被移除:结果不再计入
      if (!_items.contains(item)) return;
      switch (outcome) {
        case UploadSucceeded(:final aid):
          item
            ..aid = aid
            ..state = AttachmentState.done;
          _changed();
        case UploadFailed(:final message):
          _fail(item, message);
      }
    } on ImagePrepException catch (e) {
      _fail(item, e.message);
    } catch (_) {
      _fail(item, '图片上传失败，请重试');
    }
  }

  final _prepared = <int, PreparedImage>{};

  void _fail(ComposeImage item, String message) {
    if (!_items.contains(item)) return;
    item
      ..state = AttachmentState.failed
      ..error = message;
    _changed();
  }

  void _discard(ComposeImage item) {
    _prepared.remove(item.id);
    final path = item.path;
    if (path != null) pipeline.platform.discard(path).ignore();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final item in _items) {
      _discard(item);
    }
    super.dispose();
  }
}
