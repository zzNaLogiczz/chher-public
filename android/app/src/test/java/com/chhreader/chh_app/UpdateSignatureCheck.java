package com.chhreader.chh_app;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

/**
 * No Android runtime/JUnit needed: compile with javac and run this main class.
 * The vector was produced by Go's ecdsa.SignASN1 (the update server's signer)
 * with a throwaway key, so it proves cross-language compatibility.
 */
public final class UpdateSignatureCheck {
    private static final String KEY =
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAErctjOCByJqbQov7BlqgyGPfblaFWLr5hVbzjv1mRvzyGpdGJpAxhz0NKbR0cTic2yf3VJylVLGGtynbriIEuYg==";
    private static final String PAYLOAD =
            "eyJ0eXBlIjoiY2hlY2siLCJpc3N1ZWRBdCI6MTc5MzAwMDAwMCwidmVyc2lvbkNvZGUiOjE1MywidXBkYXRlIjp0cnVlfQ==";
    private static final String SIG =
            "MEQCIGfQItIJyOvENNSniHOSfzjCy6iMXnoQvX31Rj2/A9WTAiAy+Qhwd4AU7zDIMMarqhuDS/jRPsxD8HkigwuNJzTitg==";

    private static void expect(boolean actual, boolean expected, String what) {
        if (actual != expected) throw new AssertionError(what);
    }

    public static void main(String[] args) {
        Base64.Decoder b64 = Base64.getDecoder();
        byte[] key = b64.decode(KEY);
        byte[] payload = b64.decode(PAYLOAD);
        byte[] sig = b64.decode(SIG);

        expect(UpdateSignature.verify(key, payload, sig), true, "Go signature must verify");

        byte[] tampered = payload.clone();
        tampered[tampered.length - 2] ^= 1;
        expect(UpdateSignature.verify(key, tampered, sig), false, "tampered payload accepted");

        byte[] badSig = sig.clone();
        badSig[badSig.length - 1] ^= 1;
        expect(UpdateSignature.verify(key, payload, badSig), false, "tampered signature accepted");

        byte[] otherKey = b64.decode(
                "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE/78wN59oC99b/ClQxqXJQKC/dq63Qc8AGNJMTwd0huQPjuxjhkZkqBfWq2Jt/4fedMhTfxd89+V8lQD7iUFUTg==");
        expect(UpdateSignature.verify(otherKey, payload, sig), false, "wrong key accepted");
        expect(UpdateSignature.verify(new byte[] {1, 2}, payload, sig), false, "garbage key accepted");
        expect(UpdateSignature.verify(key, payload, null), false, "null signature accepted");

        expect(UpdateSignature.sha256Hex("abc".getBytes(StandardCharsets.UTF_8))
                .equals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"), true, "sha256");
        System.out.println("UpdateSignature: all 7 checks passed");
    }
}
