package com.chhreader.chh_app;

/** No Android runtime/JUnit needed: compile with javac and run this main class. */
public final class RefreshRatePolicyCheck {
    private static void expect(float rate, boolean expected) {
        if (RefreshRatePolicy.isWithinCap(rate, 120f) != expected) {
            throw new AssertionError("Unexpected 120Hz-cap eligibility for " + rate);
        }
    }

    public static void main(String[] args) {
        expect(60f, true);
        expect(90f, true);
        expect(120f, true);
        expect(120.000007629f, true);
        expect(120.5f, true);
        expect(120.5001f, false);
        expect(121f, false);
        expect(144f, false);
        expect(0f, false);
        expect(-1f, false);
        expect(Float.NaN, false);
        expect(Float.POSITIVE_INFINITY, false);
        System.out.println("RefreshRatePolicy: all 12 boundary checks passed");
    }
}
