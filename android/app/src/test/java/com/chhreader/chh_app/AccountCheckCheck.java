package com.chhreader.chh_app;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Collections;

public final class AccountCheckCheck {
    private static final String UID = "1001";

    private static String read(String path) throws Exception {
        return new String(Files.readAllBytes(Paths.get(path)), StandardCharsets.UTF_8);
    }

    private static void expect(AccountCheck.State state, int status, String html) {
        assert AccountCheck.classify(status, html, UID).state == state : "Unexpected account state";
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 1 || args.length > 2) {
            throw new IllegalArgumentException("Pass the synthetic fixture and optional offline guest evidence");
        }

        String guest = read(args[0]);
        expect(AccountCheck.State.EXPIRED, 200, guest);
        if (args.length == 2) expect(AccountCheck.State.EXPIRED, 200, read(args[1]));

        String byAction = guest.replace(" id=\"lsform\"", "");
        expect(AccountCheck.State.EXPIRED, 200, byAction);
        expect(AccountCheck.State.EXPIRED, 200, byAction.replace("&amp;", "&"));
        expect(AccountCheck.State.EXPIRED, 200, byAction.replace("&amp;", "&#38;"));
        expect(AccountCheck.State.EXPIRED, 200,
            "<HTML><body><header id=hd><form id=lsform></form></header></body></HTML>");

        String header = "<div id='um'><p><strong class='vwmy'><a href='space-uid-1001.html'>本地账号</a>"
            + "</strong><a id='myprompt'>提醒3</a><a id='pm_ntc'><em class='prompt_news_2'>私信</em>"
            + "</a></p></div>";
        String member = guest.replace("<div id=\"wp\">", header + "<div id=\"wp\">");
        AccountCheck.Result ok = AccountCheck.classify(200, member, UID);
        assert ok.state == AccountCheck.State.OK && UID.equals(ok.uid) && ok.notices == 3 && ok.messages == 2;
        assert !ok.pmHasCount;
        AccountCheck.Result counted = ok.withUnreadPm(Collections.singleton("31"));
        assert counted.messages == 1 && counted.pmHasCount && counted.notices == 3 && UID.equals(counted.uid);
        counted = ok.withUnreadPm(Collections.emptySet());
        assert counted.messages == 0 && counted.pmHasCount;
        assert ok.withUnreadPm(PmUnread.parse("<root><![CDATA[请先登录]]></root>")) == ok;
        String pmMenu = "<ul id='myprompt_menu'><li><a id='pm_ntc'><em class='prompt_news'></em>消息</a></li></ul>";
        AccountCheck.Result menu = AccountCheck.classify(200, member.replace(header, pmMenu + header), UID);
        assert menu.state == AccountCheck.State.OK && menu.notices == 3 && menu.messages == 1 && !menu.pmHasCount;
        AccountCheck.Result ignored = AccountCheck.classify(200, member.replace(header, "<script>" + pmMenu + "</script>" + header), UID);
        assert ignored.state == AccountCheck.State.OK && ignored.messages == 2;
        assert AccountCheck.classify(200, member, null).state == AccountCheck.State.OK;
        assert AccountCheck.classify(200, member, "1002").state == AccountCheck.State.FAILED;

        for (int status : new int[] { -1, 204, 302, 401, 403, 567 }) {
            expect(AccountCheck.State.FAILED, status, guest);
            expect(AccountCheck.State.FAILED, status, member);
        }
        expect(AccountCheck.State.FAILED, 200, "");
        expect(AccountCheck.State.FAILED, 200, null);
        expect(AccountCheck.State.FAILED, 200, header);
        expect(AccountCheck.State.FAILED, 200, member.replace("</html>", ""));
        expect(AccountCheck.State.FAILED, 200, member.replace("id=\"hd\"", "id=\"other\""));
        expect(AccountCheck.State.FAILED, 200, guest.replace("</html>", ""));
        expect(AccountCheck.State.FAILED, 200, guest.replace("id=\"hd\"", "data-id=\"hd\""));
        expect(AccountCheck.State.FAILED, 200, guest.replace("</html>", "<script>const s='</html>';</script>"));
        expect(AccountCheck.State.FAILED, 200, guest.replace("</html>", "<!-- </html> -->"));
        expect(AccountCheck.State.FAILED, 200, "<html><body><div id='hd'></div></body></html>");
        expect(AccountCheck.State.FAILED, 200, "<html><body><div id='hd'><form action='search.php'></form></div></body></html>");
        expect(AccountCheck.State.FAILED, 200, "<html><head><title>正在验证</title></head><body>稍候</body></html>");
        expect(AccountCheck.State.FAILED, 200,
            "<html><body><script>let page=\"<div id='hd'><form id='lsform'></form></div>\";</script></body></html>");
        expect(AccountCheck.State.FAILED, 200,
            "<html><body><noscript><div id='hd'><form id='lsform'></form></div></noscript></body></html>");
        expect(AccountCheck.State.FAILED, 200,
            "<html><body><div title=\"<div id='hd'><form id='lsform'></form></div>\"></div></body></html>");
        expect(AccountCheck.State.FAILED, 200, guest.replace("id=\"hd\">", "id=\"hd\"><div id='um'></div>"));
        expect(AccountCheck.State.FAILED, 200, guest.replace("<head>", "<head><script id='um'></script>"));
        expect(AccountCheck.State.FAILED, 200,
            guest.replace("id=\"hd\">", "id=\"hd\"><a href='member.php?action=logout'>退出</a>"));
        expect(AccountCheck.State.EXPIRED, 200, guest.replace("<head>", "<head><script>const s=\"" + header + "\";</script>"));

        long now = 1_000_000_000L;
        long due = 55 * 60 * 1000L;
        assert AccountCheck.isDue(true, now, 0, now);
        assert AccountCheck.isDue(false, 0, 0, now);
        assert !AccountCheck.isDue(false, now - due + 1, 0, now);
        assert AccountCheck.isDue(false, now - due, 0, now);
        for (int failures = 1; failures <= 3; failures++) {
            assert AccountCheck.isDue(false, now, failures, now);
        }
        assert !AccountCheck.isDue(false, now - due + 1, 4, now);
        assert AccountCheck.isDue(false, now - due, 4, now);
        assert !AccountCheck.isDue(false, now, 5, now);
        assert AccountCheck.isDue(false, now + 1, 0, now);
        assert AccountCheck.isDue(false, now + 1, 4, now);

        System.out.println("AccountCheck: classifier and 55-minute/failure scheduling checks passed");
        System.out.println(args.length == 2 ? "Synthetic and offline guest evidence: EXPIRED" : "Synthetic guest evidence: EXPIRED");
    }
}
