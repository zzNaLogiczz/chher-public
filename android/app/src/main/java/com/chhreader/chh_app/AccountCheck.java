package com.chhreader.chh_app;

import java.util.Locale;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class AccountCheck {
    public enum State { OK, EXPIRED, FAILED }

    public static final class Result {
        public final State state;
        public final String uid;
        public final int notices;
        public final int messages;
        public final boolean pmHasCount;

        private Result(State state, String uid, int notices, int messages, boolean pmHasCount) {
            this.state = state;
            this.uid = uid;
            this.notices = notices;
            this.messages = messages;
            this.pmHasCount = pmHasCount;
        }

        public Result withUnreadPm(Set<String> unread) {
            if (state != State.OK || unread == null) return this;
            return new Result(state, uid, notices, unread.size(), true);
        }
    }

    public static final Result FAILED = new Result(State.FAILED, null, 0, 0, false);
    private static final Result EXPIRED = new Result(State.EXPIRED, null, 0, 0, false);
    private static final long CHECK_INTERVAL = 55 * 60 * 1000L;

    // Consume whole quoted attributes and comments so embedded markup cannot supply page markers.
    private static final Pattern TOKEN = Pattern.compile(
        "<!--[\\s\\S]*?(?:--!?>|\\z)|<![^>]*>|<(/?)([a-z][a-z0-9:_-]*)(?=\\s|/?>)"
        + "((?:[^<>\"']++|\"[^\"]*+\"|'[^']*+')*+)>", Pattern.CASE_INSENSITIVE);
    private static final Pattern ATTRIBUTE = Pattern.compile(
        "([^\\s/<>='\"]+)(?:\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+)))?");
    private static final Pattern LOGIN_ACTION = Pattern.compile(
        "(?:^|/)member\\.php\\?mod=logging&(?:amp;|#0*38;|#x0*26;)?action=login(?:&|$)",
        Pattern.CASE_INSENSITIVE);

    private AccountCheck() {}

    public static Result classify(int httpStatus, String html, String expectedUid) {
        if (httpStatus != 200 || html == null) return FAILED;

        boolean htmlOpened = false;
        boolean siteHeader = false;
        boolean guestForm = false;
        boolean logout = false;
        boolean memberHeader = false;
        int memberOffset = -1;
        StringBuilder pageMarkup = new StringBuilder();
        Matcher tokens = TOKEN.matcher(html);
        for (int cursor = 0; tokens.find(cursor);) {
            if (htmlOpened) pageMarkup.append(html, cursor, tokens.start());
            cursor = tokens.end();
            if (tokens.group(2) == null) continue;
            String name = tokens.group(2).toLowerCase(Locale.ROOT);
            boolean closing = !tokens.group(1).isEmpty();
            if (name.equals("html")) {
                if (closing && htmlOpened) {
                    if (!siteHeader) return FAILED;
                    if (memberHeader) {
                        MessageHeader header = memberOffset >= 0
                            ? MessageHeader.parse(pageMarkup.toString(), memberOffset) : null;
                        return header != null && (expectedUid == null || expectedUid.equals(header.uid))
                            ? new Result(State.OK, header.uid, header.notices, header.messages, false) : FAILED;
                    }
                    return guestForm && !logout ? EXPIRED : FAILED;
                }
                if (!closing) htmlOpened = true;
            }
            if (htmlOpened && !closing) {
                String attrs = tokens.group(3);
                String id = attribute(attrs, "id");
                if ("hd".equals(id)) siteHeader = true;
                if ("um".equals(id) && !memberHeader) {
                    memberHeader = true;
                    if (name.equals("div")) memberOffset = pageMarkup.length();
                }
                if (name.equals("form") && ("lsform".equals(id)
                    || LOGIN_ACTION.matcher(attribute(attrs, "action")).find())) guestForm = true;
                if (name.equals("a") && attribute(attrs, "href").contains("action=logout")) logout = true;
            }
            if (!closing && isRawText(name)) {
                Matcher end = Pattern.compile("</" + name + "\\s*>", Pattern.CASE_INSENSITIVE).matcher(html);
                if (!end.find(cursor)) return FAILED;
                cursor = end.end();
                continue;
            }
            if (!closing && name.equals("plaintext")) return FAILED;
            if (htmlOpened) pageMarkup.append(html, tokens.start(), cursor);
        }
        return FAILED;
    }

    private static boolean isRawText(String name) {
        switch (name) {
            case "script": case "style": case "title": case "textarea":
            case "xmp": case "iframe": case "noembed": case "noframes": case "noscript": return true;
            default: return false;
        }
    }

    private static String attribute(String attrs, String name) {
        Matcher attributes = ATTRIBUTE.matcher(attrs);
        while (attributes.find()) {
            if (!attributes.group(1).equalsIgnoreCase(name)) continue;
            for (int value = 2; value <= 4; value++) {
                if (attributes.group(value) != null) return attributes.group(value);
            }
            break;
        }
        return "";
    }

    public static boolean isDue(boolean current, long attemptAt, int failures, long now) {
        return current || attemptAt <= 0 || now < attemptAt || (failures > 0 && failures < 4)
            || now - attemptAt >= CHECK_INTERVAL;
    }
}
