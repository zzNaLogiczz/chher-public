package com.chhreader.chh_app;

import java.util.HashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Background equivalent of lib/data/pm_unread.dart. Null means unknown. */
public final class PmUnread {
    private static final Pattern ENVELOPE = Pattern.compile(
        "\\s*(?:<\\?xml\\s+[^<>]*\\?>\\s*)?<root>\\s*<!\\[CDATA\\[([\\s\\S]*?)\\]\\]>\\s*</root>\\s*");
    private static final Pattern USERDATA = Pattern.compile("\\s*\\{\\s*'userdata'\\s*:\\s*\\{([\\s\\S]*)\\}\\s*\\}\\s*");
    private static final String QUOTED_VALUE = "'(?:[^'\\\\]|\\\\[\\s\\S])*+'";
    // The bundled Discuz template omits the closing brace of individual rows.
    private static final Pattern ROW = Pattern.compile(
        "\\s*[0-9]+\\s*:\\s*\\{\\s*'uid'\\s*:\\s*[0-9]+\\s*,\\s*'username'\\s*:\\s*" + QUOTED_VALUE
        + "\\s*,\\s*'avatar'\\s*:\\s*" + QUOTED_VALUE
        + "\\s*,\\s*'plid'\\s*:\\s*([0-9]+)\\s*,\\s*'isnew'\\s*:\\s*([0-9]+)\\s*,"
        + "\\s*'daterange'\\s*:\\s*[0-9]+\\s*\\}?\\s*");
    private static final Pattern LEADING_ZEROES = Pattern.compile("^0+");
    private static final Pattern NONZERO = Pattern.compile("[1-9]");

    private PmUnread() {}

    public static Set<String> parse(String xml) {
        if (xml == null) return null;
        Matcher envelope = ENVELOPE.matcher(xml);
        if (!envelope.matches()) return null;
        String payload = envelope.group(1);
        if (payload.contains("]]>")) return null;
        Matcher userdata = USERDATA.matcher(payload);
        if (!userdata.matches()) return null;
        String rows = userdata.group(1).trim();
        Set<String> unread = new HashSet<>();
        Matcher row = ROW.matcher(rows);
        int offset = 0;
        while (offset < rows.length()) {
            if (!row.region(offset, rows.length()).lookingAt()) return null;
            String plid = LEADING_ZEROES.matcher(row.group(1)).replaceFirst("");
            if (plid.isEmpty()) return null;
            if (NONZERO.matcher(row.group(2)).find()) unread.add(plid);
            offset = row.end();
            if (offset == rows.length()) break;
            if (rows.charAt(offset++) != ',' || offset == rows.length()) return null;
        }
        return unread;
    }
}
