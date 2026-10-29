import 'dart:async';

import 'package:chh_app/attachments/attachment_controller.dart';
import 'package:chh_app/attachments/image_pipeline.dart';
import 'package:chh_app/attachments/image_platform.dart';
import 'package:chh_app/models/models.dart';
import 'package:chh_app/parser/upload_parser.dart';
import 'package:flutter_test/flutter_test.dart';

class _Platform implements ImagePlatform {
  final discarded = <String>[];
  var opened = 0;

  @override
  Future<List<String>> pick(int max) async => ['picked://a', 'picked://b'];

  @override
  Future<SourceImage> open(String uri) async {
    opened++;
    return const SourceImage(
      handle: 1,
      width: 800,
      height: 600,
      format: SourceFormat.jpeg,
      size: 1000,
    );
  }

  @override
  Future<EncodedImage> encode(
    int handle, {
    required int maxSide,
    required int quality,
    bool png = false,
  }) async => EncodedImage('file-$opened', 1000);

  @override
  Future<EncodedImage> original(int handle) async =>
      EncodedImage('file-$opened', 1000);

  @override
  Future<void> close(int handle) async {}

  @override
  Future<void> discard(String path) async => discarded.add(path);
}

const _context = UploadContext(uid: '42', hash: 'h');

void main() {
  test('逐张上传,附件编号按选择顺序', () async {
    final order = <String>[];
    var inFlight = 0;
    final controller = AttachmentController(
      loadContext: () async => _context,
      pipeline: ImagePipeline(_Platform()),
      upload: (context, image) async {
        inFlight++;
        expect(inFlight, 1);
        order.add(image.path);
        await Future<void>.delayed(Duration.zero);
        inFlight--;
        return UploadSucceeded('${order.length}0');
      },
    );
    await controller.pick();
    expect(controller.busy, isTrue);
    await pumpEventQueue();
    expect(controller.busy, isFalse);
    expect(controller.aids, ['10', '20']);
    expect(order, ['file-1', 'file-2']);
  });

  test('失败可以重试,重试时复用已压缩的文件', () async {
    final platform = _Platform();
    var attempts = 0;
    final controller = AttachmentController(
      loadContext: () async => _context,
      pipeline: ImagePipeline(platform),
      upload: (context, image) async => ++attempts == 1
          ? const UploadFailed('图片上传失败（站点返回 9）')
          : const UploadSucceeded('7'),
    );
    controller.add(['content://x']);
    await pumpEventQueue();
    final item = controller.items.single;
    expect(item.state, AttachmentState.failed);
    expect(item.error, '图片上传失败（站点返回 9）');
    expect(controller.hasFailed, isTrue);

    controller.retry(item.id);
    await pumpEventQueue();
    expect(controller.aids, ['7']);
    expect(platform.opened, 1);
  });

  test('上传途中移除:结果不再计入,文件删掉', () async {
    final platform = _Platform();
    final gate = Completer<UploadOutcome>();
    final controller = AttachmentController(
      loadContext: () async => _context,
      pipeline: ImagePipeline(platform),
      upload: (context, image) => gate.future,
    );
    controller.add(['content://x']);
    await pumpEventQueue();
    final item = controller.items.single;
    expect(item.state, AttachmentState.uploading);
    controller.remove(item.id);
    gate.complete(const UploadSucceeded('1'));
    await pumpEventQueue();
    expect(controller.items, isEmpty);
    expect(controller.aids, isEmpty);
    expect(platform.discarded, ['file-1']);
  });

  test('拿不到上传参数时每张图都标失败,说明原因', () async {
    final controller = AttachmentController(
      loadContext: () async => null,
      pipeline: ImagePipeline(_Platform()),
      upload: (context, image) async => const UploadSucceeded('1'),
    );
    controller.add(['content://x']);
    await pumpEventQueue();
    expect(controller.items.single.error, contains('登录'));
  });

  test('超过张数上限的选择被截断', () async {
    final controller = AttachmentController(
      loadContext: () async => _context,
      pipeline: ImagePipeline(_Platform()),
      upload: (context, image) async => const UploadSucceeded('1'),
      limit: 3,
    );
    controller.add(['1', '2', '3', '4', '5']);
    expect(controller.items, hasLength(3));
    expect(controller.remaining, 0);
  });
}
