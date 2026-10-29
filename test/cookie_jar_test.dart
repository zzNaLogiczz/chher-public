/// 直连 Cookie 罐单测
///
/// 回归用:之前直连不保存 Set-Cookie,提交时只带 formhash 不带会话,
/// 被站点判成 CSRF 并以伪装成 Discuz 错误页的预制页拒绝(503「含有非法字符」)。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:chh_app/network/chh_fetcher.dart';
import 'package:chh_app/network/cookie_jar.dart';

void main() {
  test('收下 Set-Cookie 只取名值对,忽略属性', () {
    final jar = CookieJar()
      ..absorb([
        'v2x4_48dd_saltkey=abc123; expires=Sun, 23-Nov-2026 10:00:00 GMT; path=/; HttpOnly',
        'v2x4_48dd_sid=XyZ789; path=/; domain=.chiphell.com',
      ]);

    expect(jar.all['v2x4_48dd_saltkey'], 'abc123');
    expect(jar.all['v2x4_48dd_sid'], 'XyZ789');
  });

  test('同名后到的覆盖先到的', () {
    final jar = CookieJar()
      ..absorb(['v2x4_48dd_sid=old; path=/'])
      ..absorb(['v2x4_48dd_sid=new; path=/']);

    expect(jar.all['v2x4_48dd_sid'], 'new');
  });

  test('空值与 deleted 表示删除', () {
    final jar = CookieJar()
      ..absorb(['a=1', 'b=2'])
      ..absorb(['a=; expires=Thu, 01-Jan-1970 00:00:00 GMT', 'b=deleted']);

    expect(jar.all.containsKey('a'), isFalse);
    expect(jar.all.containsKey('b'), isFalse);
  });

  test('组装成请求头形态', () {
    final jar = CookieJar()..absorb(['a=1; path=/', 'b=2; path=/']);
    expect(jar.header(), 'a=1; b=2');
  });

  test('空罐不产生 Cookie 头', () {
    expect(CookieJar().header(), isNull);
  });

  test('畸形 Set-Cookie 不会污染罐', () {
    final jar = CookieJar()..absorb(['', '   ', '=novalue', 'noequalsign']);
    expect(jar.isEmpty, isTrue);
  });

  test('merge 合并外部注入的 Cookie,空值不进罐', () {
    final jar = CookieJar()
      ..absorb(['a=1'])
      ..merge({'b': '2', 'c': ''});

    expect(jar.all, {'a': '1', 'b': '2'});
  });

  _retryRuleTests();
}

/// 重发判定的回归
///
/// 判错代价是重复发帖,所以从严:只有确定没被站点处理才允许换通道。
void _retryRuleTests() {
  group('是否允许换通道重发', () {
    test('POST 收到 3xx 空响应说明已受理,不得重发', () {
      expect(const ChhResponse(301, '').rejectedBeforeApp, isFalse);
      expect(const ChhResponse(302, '').rejectedBeforeApp, isFalse);
    });

    test('传输失败可以重发', () {
      expect(const ChhResponse(-1, '').rejectedBeforeApp, isTrue);
    });

    test('WAF 拦截页与挑战页可以重发', () {
      expect(const ChhResponse(567, '').rejectedBeforeApp, isTrue);
      expect(
        const ChhResponse(200, 'Invalid Request').rejectedBeforeApp,
        isTrue,
      );
      expect(
        const ChhResponse(503, '您当前的访问请求当中含有非法字符').rejectedBeforeApp,
        isTrue,
      );
      expect(const ChhResponse(200, 'EO_Bot_Ssid=1').rejectedBeforeApp, isTrue);
    });

    test('真实业务响应一律不得重发', () {
      expect(
        const ChhResponse(200, '<div id="postlist"></div>').rejectedBeforeApp,
        isFalse,
      );
      expect(
        const ChhResponse(200, '抱歉,您两次发表间隔少于 10 秒').rejectedBeforeApp,
        isFalse,
      );
    });
  });
}
