package com.KoreAppsTek.PhoneStorageCleaner

/** Pure evidence ledger. A prompt, an attempted API call or an unreadable
 * verification cursor is never evidence of deletion. Sizes are logical bytes
 * read before a confirmed removal, not a free-volume/time-based estimate. */
class DeleteProgressLedger(
    private val id: String?, uris: List<String>,
    private val send: (Map<String, Any?>) -> Unit,
) {
    private val requested = uris.toSet()
    private val outcomes = linkedMapOf<String, String>()
    private val sizes = linkedMapOf<String, Long>()
    private var sequence = 0L
    private var terminal = false
    fun update(phase: String, uri: String? = null) {
        if (!terminal) emit(phase, uri)
    }
    fun settle(uri: String, outcome: String, bytes: Long? = null) {
        if (terminal || uri !in requested || uri in outcomes ||
            outcome !in setOf("deleted", "failed", "skipped")) return
        outcomes[uri] = outcome
        if (outcome == "deleted" && bytes != null && bytes >= 0) sizes[uri] = bytes
        emit("deleting", uri)
    }
    fun finish(cancelled: Boolean) {
        if (terminal) return
        terminal = true
        emit(if (cancelled) "cancelled" else "finished", null)
    }
    fun hasOutcome(uri: String): Boolean = uri in outcomes
    fun byteSizes(): Map<String, Long> = sizes.toMap()
    fun skipped(): List<String> = outcomes.filterValues { it == "skipped" }.keys.toList()
    private fun emit(phase: String, uri: String?) {
        if (id == null) return
        send(mapOf("requestId" to id, "sequence" to ++sequence,
            "total" to requested.size, "processed" to outcomes.size,
            "outcomes" to outcomes.toMap(), "confirmedBytesByUri" to sizes.toMap(),
            "currentUri" to uri, "phase" to phase, "terminal" to terminal))
    }
    companion object {
        private val requestCodes = java.util.concurrent.atomic.AtomicInteger(0)
        // Stay inside Android's 16-bit request-code range. Codes are shared
        // across bridge instances so late callbacks cannot resolve a new run.
        fun nextRequestCode(): Int = 0x4000 or (requestCodes.getAndIncrement() and 0x3fff)
        /** Nullable query result: null is unavailable, not 'file gone'. */
        fun afterConfirmation(before: Boolean?, after: Boolean?): String = when {
            before == false -> "skipped"
            before == true && after == false -> "deleted"
            else -> "failed"
        }
        fun directRows(rows: Int): String = if (rows > 0) "deleted" else "skipped"
    }
}
