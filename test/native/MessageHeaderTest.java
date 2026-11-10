package com.chhreader.chh_app;

public final class MessageHeaderTest {
    private static String page(String links) {
        return "<div id='um'><div class='avt'><img src='avatar'></div>"
            + "<p><strong class='vwmy'><a href='space-uid-1001.html'>示例账号</a></strong>"
            + links + "</p></div>";
    }
    public static void main(String[] args) {
        MessageHeader header = MessageHeader.parse(page("<a id='myprompt' class='a showmenu'>提醒<span class='num'>3</span></a><a id='pm_ntc'><em class='prompt_news_2'>消息</em></a>"));
        assert header != null && header.uid.equals("1001") && header.notices == 3 && header.messages == 2;
        header = MessageHeader.parse(page("<a id='myprompt' class='a showmenu'>提醒</a><a id='pm_ntc'><em class='prompt_news_0'>私信</em></a>"));
        assert header != null && header.notices == 0 && header.messages == 0;
        assert MessageHeader.parse("<div>WAF challenge</div>") == null;
        assert MessageHeader.parse(page("<a id='myprompt'>提醒3</a>")) == null;
        assert MessageHeader.parse(page("<a id='myprompt'>9999999999999999999</a><a id='pm_ntc'>0</a>")) == null;
        assert MessageHeader.parse("<div id='um'>游客</div>" + page("<a id='myprompt'>提醒3</a><a id='pm_ntc'>2</a>")) == null;
        header = MessageHeader.parse(page("<a id='myprompt'>提醒(7)</a><a id='pm_ntc'>0</a>").replace("space-uid-1001.html", "home.php?mod=space&amp;uid=1001"));
        assert header != null && header.uid.equals("1001") && header.notices == 7;
        System.out.println("MessageHeaderTest passed");
    }
}
