import 'package:chh_app/network/chh_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Fixture parsers stay on the widget test's fake clock.
Future<R> parseForumInline<M, R>(ComputeCallback<M, R> parse, M input) async =>
    parse(input);

void useInlineForumParser(ChhClient client) {
  client.setParserDispatchForTesting(parseForumInline);
  addTearDown(() => client.setParserDispatchForTesting(null));
}
