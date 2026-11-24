package com.chhreader.chh_app;

/** Decisions for a single UID; the caller supplies that account's saved notification state. */
public final class AccountNotificationPolicy {
    private AccountNotificationPolicy() {}

    public static boolean unreadIncreased(int priorNotices, int priorMessages, int notices, int messages) {
        return notices > priorNotices || messages > priorMessages;
    }

    public static String messageText(int notices, int messages, boolean pmHasCount) {
        String notice = notices > 0 ? notices + " 条未读提醒" : "";
        if (messages <= 0) return notice;
        String pm = pmHasCount ? messages + " 个未读对话" : "有新私信";
        return notices > 0 ? notice + "，" + pm : pm;
    }

    public static boolean enteredExpired(boolean wasExpired, boolean isExpired, boolean notifiedExpired) {
        return !wasExpired && isExpired && !notifiedExpired;
    }
}
