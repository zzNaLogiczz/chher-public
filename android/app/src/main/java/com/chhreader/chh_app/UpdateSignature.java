package com.chhreader.chh_app;

import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;

/**
 * Verifies update-server responses: ECDSA P-256 over SHA-256, DER signature,
 * SubjectPublicKeyInfo public key. Pure java.security so it can be checked
 * without an Android runtime (see UpdateSignatureCheck).
 */
public final class UpdateSignature {
    private UpdateSignature() {}

    public static boolean verify(byte[] publicKeySpki, byte[] payload, byte[] derSignature) {
        if (publicKeySpki == null || payload == null || derSignature == null) return false;
        try {
            PublicKey key = KeyFactory.getInstance("EC")
                    .generatePublic(new X509EncodedKeySpec(publicKeySpki));
            Signature verifier = Signature.getInstance("SHA256withECDSA");
            verifier.initVerify(key);
            verifier.update(payload);
            return verifier.verify(derSignature);
        } catch (Exception error) {
            // Malformed keys or signatures are simply "not verified".
            return false;
        }
    }

    public static String sha256Hex(byte[] bytes) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
            StringBuilder out = new StringBuilder(digest.length * 2);
            for (byte b : digest) out.append(String.format("%02x", b));
            return out.toString();
        } catch (Exception error) {
            throw new IllegalStateException(error);
        }
    }
}
