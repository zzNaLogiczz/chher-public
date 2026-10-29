package com.chhreader.chh_app;

/** Pure policy shared by MainActivity and the lightweight JVM boundary check. */
public final class RefreshRatePolicy {
    // Display.Mode stores a float: nominal 120Hz can be reported as 120.00001.
    public static final float CAP_TOLERANCE_HZ = 0.5f;

    private RefreshRatePolicy() {}

    public static boolean isWithinCap(float refreshRate, float nominalCap) {
        return Float.isFinite(refreshRate)
            && Float.isFinite(nominalCap)
            && nominalCap > 0f
            && refreshRate > 0f
            && refreshRate <= nominalCap + CAP_TOLERANCE_HZ;
    }
}
