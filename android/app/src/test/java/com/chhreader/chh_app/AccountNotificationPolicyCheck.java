package com.chhreader.chh_app;

public final class AccountNotificationPolicyCheck {
    public static void main(String[] args) {
        // The same incoming counts are unchanged for UID 1001 and new for UID 1002.
        assert !AccountNotificationPolicy.unreadIncreased(3, 2, 3, 2);
        assert AccountNotificationPolicy.unreadIncreased(0, 0, 3, 2);
        assert !AccountNotificationPolicy.unreadIncreased(3, 2, 2, 1);
        assert AccountNotificationPolicy.unreadIncreased(3, 2, 4, 0);
        assert AccountNotificationPolicy.unreadIncreased(3, 2, 0, 3);
        assert !AccountNotificationPolicy.unreadIncreased(0, 0, 0, 0);

        assert AccountNotificationPolicy.messageText(0, 2, true).equals("2 个未读对话");
        assert AccountNotificationPolicy.messageText(0, 1, false).equals("有新私信");
        assert AccountNotificationPolicy.messageText(3, 0, false).equals("3 条未读提醒");
        assert AccountNotificationPolicy.messageText(3, 2, true).equals("3 条未读提醒，2 个未读对话");
        assert AccountNotificationPolicy.messageText(3, 1, false).equals("3 条未读提醒，有新私信");

        assert AccountNotificationPolicy.enteredExpired(false, true, false);
        assert !AccountNotificationPolicy.enteredExpired(true, true, true);
        assert !AccountNotificationPolicy.enteredExpired(true, true, false);
        assert !AccountNotificationPolicy.enteredExpired(false, true, true);
        assert !AccountNotificationPolicy.enteredExpired(true, false, true);
        assert !AccountNotificationPolicy.enteredExpired(false, false, false);
        // After relogin or removal has cleared the UID's state, it can alert again.
        assert AccountNotificationPolicy.enteredExpired(false, true, false);

        System.out.println("AccountNotificationPolicy: unread growth and one alert per expiry checks passed");
    }
}
