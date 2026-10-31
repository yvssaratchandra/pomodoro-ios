package com.jamesblack.pomodoro.platform

import android.util.AtomicFile
import com.jamesblack.pomodoro.core.BackupCodec
import com.jamesblack.pomodoro.core.Time
import com.jamesblack.pomodoro.core.store.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.io.File
import java.time.ZoneId

class AtomicSnapshotPersistence(file: File) : SnapshotPersistence {
    private val atomic = AtomicFile(file)
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = true }

    override suspend fun load(): LocalDocument? = withContext(Dispatchers.IO) {
        if (!atomic.baseFile.exists() && !File(atomic.baseFile.path + ".bak").exists()) return@withContext null
        val bytes = atomic.openRead().use { stream ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                require(output.size() + count <= 55_000_000) { "Stored data exceeds the supported size." }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
        val envelope = json.parseToJsonElement(bytes.decodeToString(throwOnInvalidSequence = true)).jsonObject
        require(envelope["version"]?.jsonPrimitive?.int == 1) { "This stored data version is not supported." }
        val snapshot = BackupCodec.decode(requireNotNull(envelope["snapshot"]).toString().encodeToByteArray(), Time.now(), ZoneId.systemDefault(), false)
        val document = json.decodeFromJsonElement<LocalDocument>(JsonObject(envelope + ("snapshot" to json.encodeToJsonElement(snapshot))))
        require(document.alarmTickets.map { it.timerID }.distinct().size == document.alarmTickets.size) { "Invalid stored alarm records." }
        require(document.alarmTickets.all { it.deadline.isFinite() }) { "Invalid stored alarm deadline." }
        require(document.alarmTickets.size <= 64 && document.alarmTickets.all {
            runCatching { java.util.UUID.fromString(it.timerID).toString().equals(it.timerID, ignoreCase = true) }.getOrDefault(false)
        }) { "Invalid stored alarm records." }
        document
    }

    override suspend fun save(document: LocalDocument) = withContext(Dispatchers.IO) {
        val bytes = json.encodeToString(LocalDocument.serializer(), document).encodeToByteArray()
        val stream = atomic.startWrite()
        try {
            stream.write(bytes)
            atomic.finishWrite(stream)
        } catch (error: Exception) {
            atomic.failWrite(stream)
            throw error
        }
    }
}
