import 'package:chh_app/core/link_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('站内帖子', () {
    test('伪静态地址', () {
      final t = classifyLink(
        'https://www.chiphell.com/thread-2907156-1-1.html',
      );
      expect(t, isA<ThreadLink>());
      expect((t as ThreadLink).tid, 2907156);
      expect(t.pid, isNull);
    });

    test('相对地址、无 www、大写 host 都算本站', () {
      for (final href in [
        'thread-2907156-1-1.html',
        'https://chiphell.com/thread-2907156-1-1.html',
        'https://WWW.ChipHell.com/thread-2907156-2-1.html',
        'forum.php?mod=viewthread&tid=2907156&extra=page%3D1',
      ]) {
        expect(classifyLink(href), isA<ThreadLink>(), reason: href);
        expect((classifyLink(href) as ThreadLink).tid, 2907156, reason: href);
      }
    });

    test('findpost 定位到楼层', () {
      final t = classifyLink(
        'forum.php?mod=redirect&goto=findpost&ptid=2907156&pid=60783019',
      );
      expect(t, isA<ThreadLink>());
      expect((t as ThreadLink).tid, 2907156);
      expect(t.pid, 60783019);
    });

    test('tid 不是正整数时不算帖子', () {
      expect(
        classifyLink('forum.php?mod=viewthread&tid=abc'),
        isA<OtherSiteLink>(),
      );
      expect(classifyLink('thread-0-1-1.html'), isA<OtherSiteLink>());
    });

    test('非默认端口或带 userinfo 不算本站', () {
      for (final href in [
        'http://www.chiphell.com:81/forum.php?mod=redirect&goto=findpost&ptid=1&pid=2',
        'https://user@www.chiphell.com/thread-1-1-1.html',
      ]) {
        expect(classifyLink(href), isA<ExternalLink>(), reason: href);
      }
    });

    test('帖子与文章的打开地址一律重新拼成规范的 https 地址', () {
      expect(
        classifyLink(
          'http://www.chiphell.com/thread-2907156-3-1.html',
        )!.uri.toString(),
        'https://www.chiphell.com/thread-2907156-1-1.html',
      );
      expect(
        classifyLink(
          'http://chiphell.com/forum.php?mod=redirect&goto=findpost&ptid=2907156&pid=60783019&extra=x',
        )!.uri.toString(),
        'https://www.chiphell.com/forum.php?mod=redirect&goto=findpost&ptid=2907156&pid=60783019',
      );
      expect(
        classifyLink('portal.php?mod=view&aid=50001&x=1')!.uri.toString(),
        'https://www.chiphell.com/article-50001-1.html',
      );
    });

    test('仿冒域名不算本站', () {
      expect(
        classifyLink('https://www.chiphell.com.evil.cn/thread-1-1-1.html'),
        isA<ExternalLink>(),
      );
    });
  });

  group('门户文章', () {
    test('伪静态与 portal.php 两种形式', () {
      for (final href in [
        'https://www.chiphell.com/article-50001-1.html',
        'portal.php?mod=view&aid=50001',
      ]) {
        final t = classifyLink(href);
        expect(t, isA<ArticleLink>(), reason: href);
        expect((t as ArticleLink).aid, 50001, reason: href);
      }
    });
  });

  group('B 站视频', () {
    test('视频页链接', () {
      for (final href in [
        'https://www.bilibili.com/video/BV1Tvpb6HEJe',
        'https://m.bilibili.com/video/BV1Tvpb6HEJe/?share_source=copy',
        'https://www.bilibili.com/video/BV1Tvpb6HEJe?p=1',
      ]) {
        final t = classifyLink(href);
        expect(t, isA<BilibiliVideo>(), reason: href);
        expect((t as BilibiliVideo).bvid, 'BV1Tvpb6HEJe', reason: href);
      }
    });

    test('分 P 与 av 号', () {
      final p2 = classifyLink(
        'https://www.bilibili.com/video/BV1Tvpb6HEJe?p=2',
      );
      expect((p2 as BilibiliVideo).page, 2);
      final av = classifyLink('https://www.bilibili.com/video/av90400700');
      expect((av as BilibiliVideo).aid, 90400700);
      expect(av.bvid, isNull);
    });

    test('站点内嵌的 bvid 缺 BV 前缀时补上', () {
      final v = bilibiliFromEmbed(
        "document.getElementById('flv_lgA').innerHTML=(\"<iframe src='https://player.bilibili.com/player.html?bvid=1Tvpb6HEJe&autoplay=0' border='0'></iframe>\");",
      );
      expect(v!.bvid, 'BV1Tvpb6HEJe');
      expect(
        v.playerUrl.toString(),
        'https://player.bilibili.com/player.html?bvid=BV1Tvpb6HEJe&p=1&autoplay=1&danmaku=0&high_quality=1',
      );
    });

    test('内嵌的 aid 形式', () {
      final v = bilibiliFromEmbed(
        "<iframe src='https://player.bilibili.com/player.html?aid=90400700&autoplay=0'></iframe>",
      );
      expect(v!.aid, 90400700);
      expect(v.playerUrl.queryParameters['aid'], '90400700');
    });

    test('在浏览器打开时用视频页地址', () {
      final v = bilibiliFromEmbed(
        'https://player.bilibili.com/player.html?bvid=1Tvpb6HEJe&p=2',
      )!;
      expect(
        v.pageUrl.toString(),
        'https://www.bilibili.com/video/BV1Tvpb6HEJe?p=2',
      );
      final av = bilibiliFromEmbed(
        'https://player.bilibili.com/player.html?aid=90400700',
      )!;
      expect(
        av.pageUrl.toString(),
        'https://www.bilibili.com/video/av90400700',
      );
    });

    test('播放器内的跳转（手机上会跳到 blackboard 移动版播放器）', () {
      for (final url in [
        'https://player.bilibili.com/player.html?bvid=BV1Tvpb6HEJe',
        'https://www.bilibili.com/blackboard/html5mobileplayer.html?bvid=BV1Tvpb6HEJe',
        'https://www.bilibili.com/blackboard/webplayer/mbplayer.html?bvid=BV1',
      ]) {
        expect(isBilibiliPlayerPage(Uri.parse(url)), isTrue, reason: url);
      }
      for (final url in [
        'https://www.bilibili.com/video/BV1Tvpb6HEJe',
        'https://space.bilibili.com/1',
        'bilibili://video/1',
        'https://evil.com/blackboard/x.html',
      ]) {
        expect(isBilibiliPlayerPage(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('没有播放器地址的脚本不算视频', () {
      expect(bilibiliFromEmbed('zoom(this, this.src, 0, 0, 0)'), isNull);
    });

    test('短链与个人主页按站外链接处理', () {
      expect(classifyLink('https://b23.tv/9DNSjRO'), isA<ExternalLink>());
      expect(
        classifyLink('https://space.bilibili.com/1975692083/upload/video'),
        isA<ExternalLink>(),
      );
    });
  });

  group('其他', () {
    test('本站其他页面', () {
      expect(classifyLink('forum-319-1.html'), isA<OtherSiteLink>());
      expect(classifyLink('space-uid-5.html'), isA<OtherSiteLink>());
    });

    test('站外链接', () {
      final t = classifyLink('https://www.ithome.com/1/017/453.htm');
      expect(t, isA<ExternalLink>());
      expect(t!.uri.toString(), 'https://www.ithome.com/1/017/453.htm');
    });

    test('不是可打开的链接时返回 null', () {
      for (final href in ['', '#', 'javascript:;', 'mailto:a@b.c', '  ']) {
        expect(classifyLink(href), isNull, reason: href);
      }
    });

    test('同一目标的身份相同，便于去重', () {
      expect(
        classifyLink('thread-2907156-1-1.html')!.key,
        classifyLink('forum.php?mod=viewthread&tid=2907156')!.key,
      );
      expect(
        classifyLink('https://www.bilibili.com/video/BV1Tvpb6HEJe')!.key,
        bilibiliFromEmbed(
          'https://player.bilibili.com/player.html?bvid=1Tvpb6HEJe&autoplay=0',
        )!.key,
      );
    });
  });
}
