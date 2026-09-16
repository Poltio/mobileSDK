package com.poltio.sdk

import android.net.Uri
import java.net.URI

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

/** The non-alphanumeric subset of [POLTIO_URL_ALLOWED_CHARS], as the `allow` string `Uri.encode` expects. */
private val POLTIO_URL_ALLOWED_SYMBOLS: String =
    POLTIO_URL_ALLOWED_CHARS.filterNot { it.isLetterOrDigit() }.joinToString("")

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
        // without double-encoding already-valid sequences (e.g. "%20" staying "%20"). Uses
        // `Uri.decode` rather than `URLDecoder` — the latter is meant for
        // `application/x-www-form-urlencoded` query strings and would incorrectly turn a literal
        // '+' anywhere in the URL into a space. Unlike `URLDecoder`, `Uri.decode` never throws on
        // a malformed escape — it silently substitutes replacement bytes instead — so a malformed
        // escape is detected up front and decoding is skipped entirely for the whole string
        // (matching iOS's `removingPercentEncoding`, which returns nil the same way).
        val decoded = if (hasOnlyWellFormedPercentEscapes(trimmed)) Uri.decode(trimmed) else trimmed
        val encoded = encodeAllowing(decoded)
        return if (isWellFormedUrl(encoded)) encoded else trimmed
    }

    if (isWellFormedUrl(trimmed)) return trimmed

    val cleanPath = trimmed.trim('/')
    return "https://app.poltio.com/$cleanPath"
}

/** Whether every `%` in [s] is followed by exactly two hex digits — i.e. safe to percent-decode. */
private fun hasOnlyWellFormedPercentEscapes(s: String): Boolean {
    var i = 0
    while (i < s.length) {
        if (s[i] == '%') {
            if (i + 2 >= s.length || !isHexDigit(s[i + 1]) || !isHexDigit(s[i + 2])) return false
            i += 3
        } else {
            i++
        }
    }
    return true
}

private fun isHexDigit(c: Char): Boolean = c in '0'..'9' || c in 'a'..'f' || c in 'A'..'F'

private fun isWellFormedUrl(candidate: String): Boolean = try {
    val uri = URI(candidate)
    uri.scheme != null && uri.host != null
} catch (error: Exception) {
    false
}

/**
 * Percent-encodes everything in [input] outside [POLTIO_URL_ALLOWED_SYMBOLS] (plus the
 * alphanumerics `Uri.encode` always treats as safe). Delegates to `Uri.encode` rather than a
 * hand-rolled `Char`-by-`Char` loop — Kotlin `String`s iterate UTF-16 code *units*, so a manual
 * loop splits surrogate pairs (e.g. emoji) and mangles them into `%EF%BF%BD` replacement bytes;
 * `Uri.encode` operates on whole code points and encodes them correctly.
 */
private fun encodeAllowing(input: String): String = Uri.encode(input, POLTIO_URL_ALLOWED_SYMBOLS)
