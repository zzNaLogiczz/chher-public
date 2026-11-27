import 'dart:io';

import 'package:chh_app/data/smiley_store.dart';
import 'package:chh_app/network/chh_client.dart';
import 'package:chh_app/network/chh_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fetcher extends ChhFetcher {
  _Fetcher(this.response);

  ChhResponse response;
  final urls = <Uri>[];
  final requestHeaders = <Map<String, String>?>[];

  @override
  String get name => 'smiley-fixture';

  @override
  Future<ChhResponse> getHtml(Uri url, {Map<String, String>? headers}) async {
    urls.add(url);
    requestHeaders.add(headers);
    return response;
  }
}

void main() {
  final fixture = File(
    'test/fixtures/common_smilies_var.js',
  ).readAsStringSync();
  final site = Uri.parse('http://127.0.0.1:8090');

  test('discuz fixture preserves categories, codes and image paths', () {
    final catalog = SmileyCatalog.parse(fixture, siteBase: site);
    expect(catalog.groups.map((group) => group.name), ['默认', '酷猴', '呆呆男']);
    expect(catalog.groups.map((group) => group.entries.length), [24, 16, 24]);
    expect(
      catalog.byCode[":'("]?.url,
      '$site/static/image/smiley/default/cry.gif',
    );
    expect(
      catalog.byCode['{:2_25:}']?.url,
      '$site/static/image/smiley/coolmonkey/01.gif',
    );
    expect(
      catalog.codePattern
          .allMatches("文字 :'( {:2_25:} :)")
          .map((match) => match[0]),
      [":'(", '{:2_25:}', ':)'],
    );
  });

  test(
    'parses escaped strings, special segments and multiple Discuz pages',
    () {
      final catalog = SmileyCatalog.parse(r'''
      smilies_type ["_7"] = [ '分类\' [乙] \u56fe', "中文 & 队#2", ];
      smilies_type['_88'] = ['空分类', 'empty'];
      smilies_type['_99'] = ['无效目录', '..'];
      smilies_array[7][2] = [[2, ':)长', '图 #2?.gif', 20, 20,],];
      smilies_array[7][99999999999999999999999999] = [[4, ':O', 'ignored.gif']];
      smilies_array['7']["1"] = [
        [1, ":)", "图'1.gif", '20','20','20'],
        ['non-numeric-id', ':X', 'bad.gif'],
        [3, ':Y', '../elsewhere.gif'],
      ];
      smilies_array[99][1] = [['5', ':Z', 'a.gif']];
      smilies_array[123][1] = [['6', ':P', 'orphan.gif']];
      unexpected();
    ''');
      final group = catalog.groups.single;
      expect(group.name, "分类' [乙] 图");
      expect(group.entries.map((entry) => entry.code), [':)', ':)长']);
      final image = Uri.parse(group.entries.last.url);
      expect(image.host, 'www.chiphell.com');
      expect(image.hasQuery, isFalse);
      expect(image.hasFragment, isFalse);
      expect(image.pathSegments, [
        'static',
        'image',
        'smiley',
        '中文 & 队#2',
        '图 #2?.gif',
      ]);
      expect(catalog.codePattern.firstMatch(':)长')?[0], ':)长');
    },
  );

  test(
    'loads once through existing fetchers and restores the exact disk cache offline',
    () async {
      final directory = await Directory.systemTemp.createTemp('smiley-store');
      addTearDown(() => directory.delete(recursive: true));
      final cacheFile = File('${directory.path}/catalog.js');
      final blocked = _Fetcher(const ChhResponse(567, 'Invalid Request'));
      final available = _Fetcher(ChhResponse(200, fixture));
      final store = SmileyStore(
        ChhClient(fetchers: [blocked, available]),
        cacheFile: cacheFile,
        siteBase: site,
      );
      expect(await store.readCache(), isNull);
      expect(blocked.urls, isEmpty);
      final loads = await Future.wait([store.load(), store.load()]);
      expect(loads[0], same(loads[1]));
      expect(await store.load(), same(loads[0]));
      expect(available.urls, [
        site.resolve('/data/cache/common_smilies_var.js'),
      ]);
      expect(available.urls, blocked.urls);
      expect(
        available.requestHeaders.single?['X-Requested-With'],
        'XMLHttpRequest',
      );
      expect(await cacheFile.readAsString(), fixture);

      final offline = _Fetcher(const ChhResponse(-1, ''));
      final reopened = SmileyStore(
        ChhClient(fetchers: [offline]),
        cacheFile: cacheFile,
        siteBase: site,
      );
      final cached = await reopened.readCache();
      expect(cached?.byCode.keys, loads[0].byCode.keys);
      expect(await reopened.load(), same(cached));
      expect(offline.urls, isEmpty);
    },
  );

  test(
    'invalid responses never replace the cache and a retry fetches again',
    () async {
      final directory = await Directory.systemTemp.createTemp('smiley-store');
      addTearDown(() => directory.delete(recursive: true));
      final cacheFile = File('${directory.path}/catalog.js');
      final fetcher = _Fetcher(const ChhResponse(200, '<html>站点暂不可用</html>'));
      final store = SmileyStore(
        ChhClient(fetchers: [fetcher]),
        cacheFile: cacheFile,
      );

      await expectLater(store.load(), throwsFormatException);
      expect(await cacheFile.exists(), isFalse);
      fetcher.response = ChhResponse(200, fixture);
      expect((await store.load()).byCode[':)'], isNotNull);
      expect(fetcher.urls, hasLength(2));
      expect(await cacheFile.readAsString(), fixture);
    },
  );
}
