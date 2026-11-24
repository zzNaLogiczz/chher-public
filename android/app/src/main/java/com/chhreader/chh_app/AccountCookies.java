package com.chhreader.chh_app;

import java.math.BigInteger;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeFormatterBuilder;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoField;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;

final class AccountCookies {
    private static final long FALLBACK_AGE_SECONDS = 2592000;
    private static final String DOMAIN = ".chiphell.com";
    private static final Pattern DISCUZ_AUTH_NAME = Pattern.compile("[A-Za-z0-9]{4}_[A-Za-z0-9]{4}_auth");
    private static final DateTimeFormatter[] DATE_FORMATS = {
        dateFormat("d MMM uuuu HH:mm:ss z"),
        dateFormat("d-MMM-uuuu HH:mm:ss z"),
        new DateTimeFormatterBuilder().parseCaseInsensitive().appendPattern("d-MMM-")
            .appendValueReduced(ChronoField.YEAR, 2, 2, 1970).appendPattern(" HH:mm:ss z").toFormatter(Locale.US),
        dateFormat("MMM d HH:mm:ss uuuu")
    };

    private AccountCookies() {}

    static String name(String raw) {
        String pair = raw.split(";", 2)[0];
        int equals = pair.indexOf('=');
        return equals > 0 ? pair.substring(0, equals).trim() : "";
    }

    static List<String> normalize(String header) {
        List<String> cookies = new ArrayList<>();
        if (header == null) return cookies;
        for (String pair : header.split(";")) {
            String name = name(pair);
            if (name.isEmpty()) continue;
            cookies.add(name + "=" + value(pair) + "; Domain=" + DOMAIN + "; Path=/; Secure; Max-Age="
                + FALLBACK_AGE_SECONDS
                + (isCredential(name, "auth") || isCredential(name, "saltkey") ? "; HttpOnly" : ""));
        }
        return cookies;
    }

    static boolean isCredential(String name, String suffix) {
        return name.length() > suffix.length() && name.endsWith(suffix);
    }

    static boolean hasAuth(List<String> cookies) {
        for (String raw : cookies) {
            if (isCredential(name(raw), "auth") && hasCredentialValue(raw)) return true;
        }
        return false;
    }

    static String inferPrefix(List<String> cookies) {
        for (String raw : cookies) {
            String name = name(raw);
            if (!isCredential(name, "saltkey") || !hasCredentialValue(raw)) continue;
            String prefix = name.substring(0, name.length() - "saltkey".length());
            if (authValue(cookies, prefix) != null) return prefix;
        }
        return null;
    }

    static String authValue(List<String> cookies, String prefix) {
        for (String raw : cookies) {
            if (name(raw).equals(prefix + "auth") && hasCredentialValue(raw)) return value(raw);
        }
        return null;
    }

    static List<String> accountCookies(List<String> cookies, List<String> knownPrefixes) {
        Set<String> prefixes = new HashSet<>(knownPrefixes);
        Set<String> names = new HashSet<>();
        for (String raw : cookies) names.add(name(raw));
        for (String name : names) {
            if (isCredential(name, "saltkey")) {
                String prefix = name.substring(0, name.length() - "saltkey".length());
                if (prefix.endsWith("_") || names.contains(prefix + "auth")) prefixes.add(prefix);
            } else if (DISCUZ_AUTH_NAME.matcher(name).matches()) {
                prefixes.add(name.substring(0, name.length() - "auth".length()));
            }
        }
        List<String> matching = new ArrayList<>();
        for (String raw : cookies) {
            String name = name(raw);
            if (prefixes.stream().anyMatch(name::startsWith)) matching.add(raw);
        }
        // Delete auth first so an interrupted clear can be recognized on recovery.
        matching.sort(Comparator.comparing(raw -> !isCredential(name(raw), "auth")));
        return matching;
    }

    private static String value(String raw) {
        String pair = raw.split(";", 2)[0];
        return pair.substring(pair.indexOf('=') + 1).trim();
    }

    private static boolean hasCredentialValue(String raw) {
        String value = value(raw);
        if (value.length() >= 2 && value.startsWith("\"") && value.endsWith("\"")) {
            value = value.substring(1, value.length() - 1).trim();
        }
        return !value.isEmpty() && !value.equalsIgnoreCase("deleted");
    }

    static boolean isExpired(String raw, long savedAt, long now) {
        String maxAge = attribute(raw, "Max-Age");
        if (maxAge != null && maxAge.matches("-?[0-9]+")) {
            BigInteger seconds = new BigInteger(maxAge);
            return seconds.signum() <= 0 ||
                seconds.multiply(BigInteger.valueOf(1000)).add(BigInteger.valueOf(savedAt))
                    .compareTo(BigInteger.valueOf(now)) <= 0;
        }
        String expires = attribute(raw, "Expires");
        if (expires == null) return false;
        // Ignore the weekday, which isn't used for expiry by browsers.
        String date = expires.replaceFirst("^[A-Za-z]{3,9}\\b[ ,]+", "").replaceAll("\\s+", " ");
        for (DateTimeFormatter format : DATE_FORMATS) {
            try {
                LocalDateTime time = LocalDateTime.parse(date, format);
                return time.toInstant(ZoneOffset.UTC).toEpochMilli() <= now;
            } catch (DateTimeParseException ignored) {
                // Unrecognized expiry attributes leave session cookies intact.
            }
        }
        return false;
    }

    private static DateTimeFormatter dateFormat(String pattern) {
        return new DateTimeFormatterBuilder().parseCaseInsensitive().appendPattern(pattern).toFormatter(Locale.US);
    }

    static List<String> deletions(String raw, boolean hasCookieInfo) {
        String prefix = name(raw) + "=; Max-Age=0; Secure; Path=";
        String path = hasCookieInfo ? attribute(raw, "Path") : null;
        prefix += path == null ? "/" : path;
        String domain = hasCookieInfo ? attribute(raw, "Domain") : null;
        if (domain != null && !domain.isEmpty()) {
            return Arrays.asList(prefix + "; Domain=" + domain);
        }
        return Arrays.asList(prefix, prefix + "; Domain=" + DOMAIN);
    }

    private static String attribute(String raw, String name) {
        String[] parts = raw.split(";");
        for (int i = 1; i < parts.length; i++) {
            String[] pair = parts[i].split("=", 2);
            if (pair.length == 2 && pair[0].trim().equalsIgnoreCase(name)) return pair[1].trim();
        }
        return null;
    }
}
