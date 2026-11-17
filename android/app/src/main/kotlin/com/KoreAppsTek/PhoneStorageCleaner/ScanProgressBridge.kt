package com.KoreAppsTek.PhoneStorageCleaner

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CancellationException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

/** Engine-local progress transport. Work never waits for a Dart acknowledgement. */
class ScanProgressBridge(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    companion object { const val CHANNEL = "com.KoreAppsTek.PhoneStorageCleaner/scan_progress" }
    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())
    private val active = ConcurrentHashMap<String, NativeScanProgress>()
    @Volatile private var disposed = false
    init { channel.setMethodCallHandler(this) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancel") {
            call.argument<String>("requestId")?.let { active[it]?.cancel() }
            result.success(null)
        } else result.notImplemented()
    }

    fun request(call: MethodCall): NativeScanProgress {
        val id = call.argument<String>("progressId")
        val progress = NativeScanProgress(id, { task -> handler.post(task) }, { payload ->
            if (!disposed) channel.invokeMethod("progress", payload)
        }, { if (id != null) active.remove(id) })
        if (id != null) active[id] = progress
        return progress
    }

    fun dispose() {
        disposed = true
        active.values.forEach { it.cancel() }
        active.clear()
        channel.setMethodCallHandler(null)
    }
}

class NativeScanProgress(
    private val id: String?,
    private val post: (() -> Unit) -> Unit,
    private val send: (Map<String, Any?>) -> Unit,
    private val release: () -> Unit,
    private val clock: () -> Long = { SystemClock.elapsedRealtime() },
) {
    private val cancelled = AtomicBoolean(false)
    private val finished = AtomicBoolean(false)
    private val posted = AtomicBoolean(false)
    private val pending = LinkedHashMap<Int, Map<String, Any?>>()
    private val deliveryLock = Any()
    private var stageIndex = 0
    private var sequence = 0L
    private var lastEvent: Map<String, Any?>? = null
    private var lastSent = 0L
    private var partial = false
    var numeric = false
    private var stage = "Discovering"
    private var processed = 0
    private var total: Int? = null
    private var unit = "rows checked"
    fun cancel() { cancelled.set(true) }
    fun check() { if (cancelled.get()) throw CancellationException("Scan cancelled") }
    fun incomplete() { partial = true }

    fun update(label: String, done: Int, count: Int? = null, units: String = "rows checked", force: Boolean = false) {
        if (finished.get()) return
        val changed = label != stage || done < processed ||
            (total != null && count != null && total != count)
        if (changed) {
            // Keep the actual last counts at a boundary, even if the normal
            // sampling interval suppressed them. No scan work waits for UI.
            if (lastEvent != null) emit(if (total != null && processed == total) "stageComplete" else "running", true)
            stageIndex++
        }
        stage = label; processed = done; total = count; unit = units
        emit("running", force || changed)
    }
    private fun emit(outcome: String, force: Boolean) {
        if (id == null) return
        val now = clock()
        if (!force && now - lastSent < 80L) return
        lastSent = now
        val event = mapOf("requestId" to id, "stageIndex" to stageIndex,
            "sequence" to ++sequence, "stage" to stage,
            "processed" to processed, "total" to total,
            "numeric" to numeric, "unit" to unit, "outcome" to outcome)
        lastEvent = event
        synchronized(deliveryLock) {
            // Coalesce within each stage, not across stage boundaries. Bounded
            // backlog skips very fast undisplayed stages instead of flashing.
            pending[stageIndex] = event
            while (pending.size > 16) pending.remove(pending.keys.first())
            if (posted.compareAndSet(false, true)) post {
                val batch = synchronized(deliveryLock) {
                    val values = pending.values.toList()
                    pending.clear()
                    posted.set(false)
                    values
                }
                batch.forEach(send)
            }
        }
    }
    private var outcome = "running"
    fun wrap(payload: Any): Any = if (id == null) payload else mapOf(
        "scanPayload" to payload, "scanOutcome" to outcome,
        "scanStage" to lastEvent,
    )
    fun finish(outcome: String = "succeeded") {
        if (!finished.compareAndSet(false, true)) return
        this.outcome = if (cancelled.get()) "cancelled" else if (partial && outcome == "succeeded") "partial" else outcome
        emit(if (cancelled.get()) "cancelled" else if (partial && outcome == "succeeded") "partial" else outcome, true)
        release()
    }
}
