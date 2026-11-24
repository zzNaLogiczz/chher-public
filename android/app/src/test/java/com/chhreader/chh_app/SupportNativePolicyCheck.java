package com.chhreader.chh_app;

public final class SupportNativePolicyCheck {
    public static void main(String[] args) {
        assert "Pictures/Chhers".equals(SupportNativePolicy.RELATIVE_PATH);
        assert SupportNativePolicy.isPngDisplayName("Chhers-Alipay.png");
        assert SupportNativePolicy.isPngDisplayName("Chhers-微信.png");
        assert "Chhers-WeChat-1.png".equals(
            SupportNativePolicy.numberedDisplayName("Chhers-WeChat.png", 1));
        for (String invalid : new String[] {
            null, "", ".png", ".hidden.png", "../test.png", "new/test.png", "new\\test.png",
            "test\ntest.png", "test.jpg", new String(new char[240]).replace('\0', 'x') + ".png"
        }) {
            assert !SupportNativePolicy.isPngDisplayName(invalid) : invalid;
        }

        assert "com.tencent.mm".equals(SupportNativePolicy.WECHAT_PACKAGE);
        assert "com.tencent.mm.ui.LauncherUI".equals(SupportNativePolicy.WECHAT_LAUNCHER);
        assert "LauncherUI.From.Scaner.Shortcut".equals(SupportNativePolicy.WECHAT_SCAN_EXTRA);
        assert SupportNativePolicy.WECHAT_SCAN_VALUE;
        assert SupportNativePolicy.WECHAT_SCAN_FLAGS == 0x14000000;
        System.out.println("SupportNativePolicy: MediaStore names/path and WeChat scan intent checks passed");
    }
}
