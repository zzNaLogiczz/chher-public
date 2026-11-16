import 'package:flutter/services.dart';

import '../widgets/cached_net_image.dart';
import '../widgets/net_image.dart';

/// Keep the cached original alive while the system save destination is open.
Future<bool> saveForumImage(String url) => ChhCachedImage.withEncodedFile(
  url,
  (file) async =>
      await const MethodChannel(
        'chh/image',
      ).invokeMethod<bool>('save', {'path': file.path}) ??
      false,
  headers: chhImageHeaders,
);
