package com.chhreader.chh_app;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Conservative subset of header_parser.dart for background checks. Unknown markup is ignored. */
public final class MessageHeader {
    public final String uid;
    public final int notices;
    public final int messages;

    private MessageHeader(String uid, int notices, int messages) {
        this.uid = uid;
        this.notices = notices;
        this.messages = messages;
    }

    private static Pattern pattern(String regex) {
        return Pattern.compile(regex, Pattern.CASE_INSENSITIVE | Pattern.DOTALL);
    }

    public static MessageHeader parse(String html) {
        Matcher start = pattern("<div\\b[^>]*\\bid\\s*=\\s*['\"]um['\"][^>]*>").matcher(html);
        if (!start.find()) return null;
        Matcher tags = pattern("</?div\\b[^>]*>").matcher(html);
        tags.region(start.end(), html.length());
        int depth = 1;
        int end = -1;
        while (tags.find()) {
            depth += tags.group().startsWith("</") ? -1 : 1;
            if (depth == 0) { end = tags.start(); break; }
        }
        if (end < 0) return null;
        String header = html.substring(start.end(), end);
        Matcher user = pattern("<strong\\b[^>]*>\\s*<a\\b[^>]*\\bhref\\s*=\\s*['\"]([^'\"]+)['\"][^>]*>[^<]+</a>").matcher(header);
        if (!user.find()) return null;
        String href = user.group(1).replace("&amp;", "&");
        Matcher uid = pattern("(?:space-uid-|[?&]uid=)([1-9][0-9]*)(?:[.&]|$)").matcher(href);
        if (!uid.find()) return null;
        Integer notices = count(header, "myprompt");
        Integer messages = count(header, "pm_ntc");
        if (notices == null || messages == null) return null;
        return new MessageHeader(uid.group(1), notices, messages);
    }

    private static Integer count(String header, String id) {
        Matcher link = pattern("<a\\b[^>]*\\bid\\s*=\\s*['\"]" + id + "['\"][^>]*>(.*?)</a>").matcher(header);
        if (!link.find()) return null;
        String body = link.group(1);
        Matcher count = pattern("\\bclass\\s*=\\s*['\"][^'\"]*\\bprompt_news_([0-9]+)\\b").matcher(body);
        if (!count.find()) count = pattern("([0-9]+)").matcher(body.replaceAll("<[^>]*>", ""));
        else return number(count.group(1));
        if (count.find()) return number(count.group(1));
        return 0;
    }

    private static Integer number(String value) {
        try { return Integer.valueOf(value); }
        catch (NumberFormatException ignored) { return null; }
    }
}
