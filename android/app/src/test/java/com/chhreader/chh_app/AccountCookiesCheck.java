package com.chhreader.chh_app;

import java.time.Instant;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/** Run with javac and java -ea. Uses synthetic cookies only. */
public final class AccountCookiesCheck {
    public static void main(String[] args) {
        String attributes = "; Domain=.chiphell.com; Path=/; Secure; Max-Age=2592000";
        List<String> normalized = AccountCookies.normalize(
            " edge=ok; malformed; pre_auth = token==; pre_saltkey=abc; pre_sid=456");
        assert normalized.equals(Arrays.asList("edge=ok" + attributes,
            "pre_auth=token==" + attributes + "; HttpOnly",
            "pre_saltkey=abc" + attributes + "; HttpOnly", "pre_sid=456" + attributes));
        assert AccountCookies.normalize(null).isEmpty();

        assert "pre_".equals(AccountCookies.inferPrefix(normalized));
        assert "pre_".equals(AccountCookies.inferPrefix(Arrays.asList(
            "orphan_saltkey=sample", "other_auth=sample", "pre_auth=sample", "pre_saltkey=sample")));
        assert AccountCookies.inferPrefix(Arrays.asList("pre_auth=sample", "pre_saltkey=")) == null;
        assert AccountCookies.inferPrefix(Arrays.asList("pre_auth=", "pre_saltkey=sample")) == null;
        assert AccountCookies.inferPrefix(Arrays.asList("auth=sample", "saltkey=sample")) == null;
        assert AccountCookies.inferPrefix(Collections.singletonList("pre_auth=sample")) == null;
        assert AccountCookies.hasAuth(Collections.singletonList("pre_auth=sample"));
        assert !AccountCookies.hasAuth(Collections.singletonList("pre_auth= "));
        assert !AccountCookies.hasAuth(Collections.singletonList("pre_auth=\"\""));
        assert !AccountCookies.hasAuth(Collections.singletonList("pre_auth=deleted"));
        assert AccountCookies.accountCookies(Arrays.asList("device_auth=sample", "EO_Bot_Ssid=sample",
                "pre_sid=sample", "pre_auth=sample", "old_sid=sample", "test_1234_auth=sample"),
            Arrays.asList("pre_", "old_")).equals(Arrays.asList(
                "pre_auth=sample", "test_1234_auth=sample", "pre_sid=sample", "old_sid=sample"));

        long savedAt = 10000L;
        long expiry = Instant.parse("2027-11-23T00:00:00Z").toEpochMilli();
        assert !AccountCookies.isExpired("pre_auth=sample", savedAt, expiry);
        assert !AccountCookies.isExpired("pre_auth=sample; Max-Age=10", savedAt, 19999L);
        assert AccountCookies.isExpired("pre_auth=sample; Max-Age=10", savedAt, 20000L);
        assert AccountCookies.isExpired("pre_auth=sample; Max-Age=-1", savedAt, savedAt);
        assert !AccountCookies.isExpired("pre_auth=sample; Max-Age=99999999999999999999", savedAt, expiry);
        assert !AccountCookies.isExpired("pre_auth=sample; Expires=bad date", savedAt, expiry);
        assert !AccountCookies.isExpired("pre_auth=sample; Expires=Tue, 23 Nov 2027 00:00:00 GMT", savedAt, expiry - 1);
        assert AccountCookies.isExpired("pre_auth=sample; Expires=Tue, 23 Nov 2027 00:00:00 GMT", savedAt, expiry);
        assert AccountCookies.isExpired("pre_auth=sample; Expires=Wednesday, 23-NOV-99 00:00:00 GMT", savedAt, expiry);
        assert !AccountCookies.isExpired("pre_auth=sample; Expires=Tue, 23 Nov 2027 00:00:00 GMT; max-age=10",
            expiry, expiry);
        assert AccountCookies.isExpired("pre_auth=sample; Expires=Tue, 23 Nov 2027 00:00:00 GMT; Max-Age=invalid",
            savedAt, expiry);

        assert AccountCookies.deletions("pre_auth=sample; Domain=.chiphell.com; Path=/forum", true)
            .equals(Collections.singletonList("pre_auth=; Max-Age=0; Secure; Path=/forum; Domain=.chiphell.com"));
        assert AccountCookies.deletions("pre_auth=sample; Path=/forum", true).equals(Arrays.asList(
            "pre_auth=; Max-Age=0; Secure; Path=/forum", "pre_auth=; Max-Age=0; Secure; Path=/forum; Domain=.chiphell.com"));
        assert AccountCookies.deletions(normalized.get(1), false).equals(Arrays.asList(
            "pre_auth=; Max-Age=0; Secure; Path=/", "pre_auth=; Max-Age=0; Secure; Path=/; Domain=.chiphell.com"));

        System.out.println("AccountCookies: normalization, prefix, expiry and deletion checks passed");
    }
}
