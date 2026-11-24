package com.chhreader.chh_app;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;

public final class PmUnreadTest {
    private static String ajax(String payload) {
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n<root><![CDATA[\n" + payload + "\n]]></root>";
    }

    private static String userdata(String rows) {
        return ajax("{'userdata':{" + rows + "}}");
    }

    private static String row(int uid, String username, String plid, int isnew) {
        return uid + ":{'uid':" + uid + ", 'username':'" + username + "', 'avatar':'avatar.php?uid=" + uid
            + "', 'plid':" + plid + ", 'isnew':" + isnew + ", 'daterange':1}";
    }

    public static void main(String[] args) {
        String first = row(1001, "示例\\'账号", "31", 2);
        String read = row(1002, "已读账号", "42", 0);
        String duplicate = row(1003, "相同会话", "031", 1);
        String another = row(1004, "新会话", "55", 1);
        assert PmUnread.parse(userdata(String.join(", ", first, read, duplicate, another)))
            .equals(new HashSet<>(Arrays.asList("31", "55")));
        // Discuz X3.5's getpmuser branch leaves off each entry's final brace.
        assert PmUnread.parse(userdata(String.join(",", first, read).replace("'daterange':1}", "'daterange':1")))
            .equals(Collections.singleton("31"));
        assert PmUnread.parse(userdata(read)).isEmpty();
        assert PmUnread.parse(userdata(" ")).isEmpty();
        assert PmUnread.parse(ajax("<div>请先登录</div>")) == null;
        assert PmUnread.parse("<html>出错</html>") == null;
        assert PmUnread.parse(userdata(first + ",")) == null;
        assert PmUnread.parse(userdata(first + ",invalid")) == null;
        assert PmUnread.parse(userdata(first.replace("'plid':31", "'plid':0"))) == null;
        assert PmUnread.parse(userdata(row(1001, "]]>", "31", 1))) == null;
        assert PmUnread.parse("{'userdata':{}}") == null;
        System.out.println("PmUnreadTest passed");
    }
}
