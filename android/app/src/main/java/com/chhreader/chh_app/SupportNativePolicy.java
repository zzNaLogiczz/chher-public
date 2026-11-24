package com.chhreader.chh_app;

import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

final class SupportNativePolicy {
    static final String RELATIVE_PATH = "Pictures/Chhers";
    static final String WECHAT_PACKAGE = "com.tencent.mm";
    static final String WECHAT_LAUNCHER = "com.tencent.mm.ui.LauncherUI";
    static final String WECHAT_SCAN_EXTRA = "LauncherUI.From.Scaner.Shortcut";
    static final boolean WECHAT_SCAN_VALUE = true;
    static final int WECHAT_SCAN_FLAGS = 0x14000000;
    private static final Pattern PNG_NAME =
        Pattern.compile("[^ .\\\\/:*?\"<>|\\p{Cntrl}][^\\\\/:*?\"<>|\\p{Cntrl}]*\\.png");

    private SupportNativePolicy() {}

    static boolean isPngDisplayName(String name) {
        return name != null && name.getBytes(StandardCharsets.UTF_8).length <= 240
            && PNG_NAME.matcher(name).matches();
    }

    static String numberedDisplayName(String name, int number) {
        return name.substring(0, name.length() - 4) + "-" + number + ".png";
    }
}
