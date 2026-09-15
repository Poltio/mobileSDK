package com.poltio.sdk

import java.net.URI
import java.net.URLDecoder

/**
 * Broader than a typical "query allowed" set: covers characters valid, unescaped, anywhere in a
 * URL (scheme, path, query, or fragment), so an encoding pass doesn't escape delimiters like
 * `:`, `/`, `#`, `?`. `%` is intentionally excluded — after decoding, any remaining literal `%`
 * should always be re-escaped to `%25` rather than treated as a pre-existing (and possibly
 * invalid) escape prefix.
 */
private val POLTIO_URL_ALLOWED_CHARS: Set<Char> = buildSet {
    ('a'..'z').forEach { add(it) }
    ('A'..'Z').forEach { add(it) }
    ('0'..'9').forEach { add(it) }
    "-._~:/?#[]@!$&'()*+,;=".forEach { add(it) }
}

/**
 * Sanitizes or formats a raw URL string to guarantee it contains a scheme and host required by
 * the API.
 */
internal fun sanitizeOrFormatURL(rawInput: String): String {
    val trimmed = rawInput.trim()
    if (trimmed.isEmpty()) return "https://app.poltio.com/default"

    if (trimmed.contains("://")) {
        // Decide whether encoding is needed by inspecting the actual characters present, not by
        // trusting URI parsing to reject invalid input — a lenient parser can happily accept raw,
        // unescaped spaces, so a "does it parse?" check can't distinguish "already valid" from
        // "needs encoding".
        val needsEncoding = trimmed.any { it !in POLTIO_URL_ALLOWED_CHARS }
        if (!needsEncoding) {
            // No percent signs and nothing else needs escaping — already well-formed.
            return trimmed
        }

        // Normalize by decoding any existing percent-escapes back to raw characters first, then
        // re-encoding the whole thing from scratch. This handles literal unescaped characters
        // (spaces, etc.) and stray/invalid '%' signs (e.g. "50%off" -> "50%25off") consistently,
        // without double-encoding already-valid sequences (e.g. "%20" staying "%20").
        val decoded = try {
            URLDecoder.decode(trimmed, "UTF-8")
        } catch (error: Exception) {
            trimmed
        }
        val encoded = encodeAllowing(decoded, POLTIO_URL_ALLOWED_CHARS)
        return if (isWellFormedUrl(encoded)) encoded else trimmed
    }

    if (isWellFormedUrl(trimmed)) return trimmed

    val cleanPath = trimmed.trim('/')
    return "https://app.poltio.com/$cleanPath"
}

private fun isWellFormedUrl(candidate: String): Boolean = try {
    val uri = URI(candidate)
    uri.scheme != null && uri.host != null
} catch (error: Exception) {
    false
}

private fun encodeAllowing(input: String, allowed: Set<Char>): String {
    val builder = StringBuilder()
    for (ch in input) {
        if (ch in allowed) {
            builder.append(ch)
        } else {
            for (byte in ch.toString().toByteArray(Charsets.UTF_8)) {
                builder.append('%')
                builder.append(String.format("%02X", byte))
            }
        }
    }
    return builder.toString()
}
