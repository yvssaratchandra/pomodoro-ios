package com.jamesblack.pomodoro.core

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.time.ZoneId
import java.util.UUID

object BackupCodec {
    const val maximumBytes = 50_000_000
    private val json = Json { encodeDefaults = true; explicitNulls = false; ignoreUnknownKeys = true; prettyPrint = true }
    fun encodeSaved(snapshot: AppSnapshot): ByteArray { validate(snapshot); return encode(snapshot.copy(activeTimer = null)) }
    fun encode(snapshot: AppSnapshot, forBackup: Boolean = false): ByteArray {
        require(!forBackup || snapshot.activeTimer == null) { "End the timer before exporting a backup." }; validate(snapshot)
        return json.encodeToString(snapshot).toByteArray(Charsets.UTF_8)
    }
    fun decode(bytes: ByteArray, now: Double = Time.now(), zone: ZoneId = ZoneId.systemDefault(), forBackup: Boolean = true): AppSnapshot {
        require(bytes.size <= maximumBytes) { "The backup exceeds the 50 MB limit." }
        val source = json.parseToJsonElement(bytes.toString(Charsets.UTF_8)).jsonObject
        val version = source.getValue("schemaVersion").jsonPrimitive.int
        require(version in 1..AppSnapshot.currentSchemaVersion) { "This data version is not supported." }
        val doc = source.toMutableMap()
        fun settings() = doc.getValue("settings").jsonObject.toMutableMap()
        for (current in version until AppSnapshot.currentSchemaVersion) {
            when (current) {
                1 -> { val s = settings(); s["showProjectNameOnLockScreen"] = JsonPrimitive(false); s["showIntentionOnLockScreen"] = JsonPrimitive(false); doc["settings"] = JsonObject(s) }
                2 -> { val s = settings(); val enabled = s.getValue("notificationSound").jsonPrimitive.boolean; s["focusCompletionSound"] = JsonPrimitive("systemDefault"); s["breakCompletionSound"] = JsonPrimitive("systemDefault"); doc["settings"] = JsonObject(s)
                    (doc["activeTimer"] as? JsonObject)?.let { val t = it.toMutableMap(); t["completionSound"] = JsonPrimitive(if (enabled) "systemDefault" else "silent"); doc["activeTimer"] = JsonObject(t) } }
                3 -> { val minutes = settings().getValue("dailyGoalMinutes").jsonPrimitive.int; val day = json.encodeToJsonElement(LocalDay.at(now, zone)); doc["goalPlan"] = buildJsonObject { put("dailyRevisions", buildJsonArray { add(buildJsonObject { put("effectiveFrom", day); put("minutes", JsonArray(List(7) { JsonPrimitive(minutes) })) }) }); put("weeklyProjectRevisions", JsonArray(emptyList())) } }
                4 -> Unit
                5 -> doc["thoughts"] = JsonArray(emptyList())
                6 -> { val s = settings(); s["consistencyTargetDays"] = JsonPrimitive(4); doc["settings"] = JsonObject(s) }
                7 -> require(doc.getValue("thoughts").jsonArray.all { (it.jsonObject["projectID"] as? JsonPrimitive)?.isString == true }) { "Invalid captured thoughts." }
                8 -> { val goal = doc.getValue("goalPlan").jsonObject.toMutableMap(); val today = LocalDay.at(now, zone)
                    val eligible = goal["dailyRevisions"]?.jsonArray?.mapNotNull { element -> runCatching { json.decodeFromJsonElement<DailyGoalRevision>(element) }.getOrNull() }?.filter { runCatching { it.effectiveFrom.date() }.isSuccess && it.effectiveFrom <= today && it.minutes.size == 7 }?.maxByOrNull { it.effectiveFrom }
                    goal["dailyProjectRevisions"] = JsonArray(emptyList()); goal["legacyDailyGoalTransitionDay"] = json.encodeToJsonElement(today)
                    if (eligible != null) goal["pendingLegacyDailySchedule"] = JsonArray(eligible.minutes.map(::JsonPrimitive)) else goal.remove("pendingLegacyDailySchedule")
                    doc["goalPlan"] = JsonObject(goal) }
            }
            doc["schemaVersion"] = JsonPrimitive(current + 1)
        }
        fun canonical(element: JsonElement): JsonElement = when (element) {
            is JsonObject -> JsonObject(element.mapValues { (key, value) -> if (key in setOf("id", "projectID", "originSessionID") && value is JsonPrimitive && value.isString) JsonPrimitive(value.content.uppercase()) else canonical(value) })
            is JsonArray -> JsonArray(element.map(::canonical))
            else -> element
        }
        val upgraded = canonical(JsonObject(doc)).jsonObject
        checkRequired(upgraded)
        val state = json.decodeFromJsonElement<AppSnapshot>(upgraded)
        validate(state)
        require(!forBackup || state.activeTimer == null) { "Backups cannot contain a running timer." }
        return state
    }
    // Constructor defaults help callers create fresh state; they must never repair missing stored fields.
    private fun checkRequired(doc: JsonObject) {
        fun required(obj: JsonObject, names: String) { names.split(' ').forEach { require(obj[it] != null && obj[it] != JsonNull) { "Missing required field: $it" } } }
        fun objects(key: String, names: String) { doc.getValue(key).jsonArray.forEach { required(it.jsonObject, names) } }
        required(doc, "schemaVersion projects sessions thoughts settings goalPlan completedInCycle")
        required(doc.getValue("settings").jsonObject, "dailyGoalMinutes defaultFocusMinutes defaultShortBreakMinutes defaultLongBreakMinutes longBreakInterval notificationSound focusCompletionSound breakCompletionSound haptics appearance showProjectNameOnLockScreen showIntentionOnLockScreen consistencyTargetDays")
        objects("projects", "id name status focusMinutes shortBreakMinutes longBreakMinutes createdAt")
        objects("sessions", "id projectID startedAt endedAt plannedSeconds outcome")
        objects("thoughts", "id createdAt text")
        doc.getValue("projects").jsonArray.forEach { (it.jsonObject["breadcrumb"] as? JsonObject)?.let { b -> required(b, "text updatedAt") } }
        (doc["activeTimer"] as? JsonObject)?.let { required(it, "id projectID kind startedAt plannedSeconds shortBreakMinutes longBreakMinutes longBreakInterval completionSound") }
        (doc["breakOffer"] as? JsonObject)?.let { required(it, "projectID kind minutes") }
        val goal = doc.getValue("goalPlan").jsonObject
        required(goal, "dailyRevisions weeklyProjectRevisions dailyProjectRevisions")
        listOf("dailyRevisions", "weeklyProjectRevisions", "dailyProjectRevisions").forEach { key -> goal.getValue(key).jsonArray.forEach { value -> val r = value.jsonObject; required(r, if (key == "dailyRevisions") "effectiveFrom minutes" else if (key == "weeklyProjectRevisions") "projectID effectiveFrom" else "projectID effectiveFrom minutes"); required(r.getValue("effectiveFrom").jsonObject, "year month day") } }
        (goal["legacyDailyGoalTransitionDay"] as? JsonObject)?.let { required(it, "year month day") }
    }
    fun validate(state: AppSnapshot) {
        require(state.schemaVersion == AppSnapshot.currentSchemaVersion) { "This data version is not supported." }
        val s = state.settings
        require(s.consistencyTargetDays in 1..7) { "Choose 1 to 7 focused days per week." }
        require(s.dailyGoalMinutes in 1..1440 && s.defaultFocusMinutes in 10..60 && s.defaultShortBreakMinutes in 1..60 && s.defaultLongBreakMinutes in 1..60 && s.longBreakInterval in 1..12 && state.completedInCycle in 0..11) { "Invalid timer settings." }
        fun id(value: String) { require(value.matches(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"))) { "Invalid identifier." }; UUID.fromString(value) }
        val ids = state.projects.map { it.id }.toSet()
        require(ids.size == state.projects.size && state.sessions.map { it.id }.toSet().size == state.sessions.size && state.thoughts.map { it.id }.toSet().size == state.thoughts.size) { "Duplicate identifiers in data." }
        state.projects.forEach { p -> id(p.id); require(p.name.trim().isNotEmpty() && SessionText.count(p.name) <= 100 && p.createdAt.isFinite() && p.focusMinutes in 10..60 && p.shortBreakMinutes in 1..60 && p.longBreakMinutes in 1..60 && (p.lastFocusMinutes == null || p.lastFocusMinutes in 10..60)) { "Invalid project details." }; p.breadcrumb?.let { require(SessionText.normalize(it.text) != null && it.updatedAt.isFinite()); it.originSessionID?.let(::id) } }
        fun intention(value: String?) { require(value == null || SessionText.count(value) <= 280) { "Session intentions must be 280 characters or fewer." } }
        state.sessions.forEach { v -> id(v.id); id(v.projectID); SessionText.normalize(v.nextStep); intention(v.intention); require(v.projectID in ids && v.startedAt.isFinite() && v.endedAt.isFinite() && v.plannedSeconds in 600..3600 && v.plannedSeconds % 60 == 0 && v.endedAt >= v.startedAt && v.duration <= v.plannedSeconds && (v.outcome != SessionOutcome.completed || v.duration == v.plannedSeconds.toDouble())) { "Invalid focus session." } }
        state.thoughts.forEach { v -> id(v.id); v.projectID?.let(::id); v.originSessionID?.let(::id); require((v.projectID == null || v.projectID in ids) && SessionText.normalize(v.text, 500) != null && v.createdAt.isFinite() && (v.completedAt == null || (v.completedAt.isFinite() && v.completedAt >= v.createdAt))) { "Invalid captured thought." } }
        GoalEngine.validate(state.goalPlan, ids)
        state.goalPlan.dailyProjectRevisions.forEach { id(it.projectID) }; state.goalPlan.weeklyProjectRevisions.forEach { id(it.projectID) }
        state.activeTimer?.let { t -> id(t.id); id(t.projectID); intention(t.intention); val range = if (t.kind == TimerKind.focus) 600..3600 else 60..3600
            require(t.projectID in ids && t.plannedSeconds in range && t.plannedSeconds % 60 == 0 && t.startedAt.isFinite() && t.longBreakInterval in 1..12 && state.sessions.none { it.id == t.id } && state.breakOffer == null) { "Invalid active timer." }
            if (t.kind == TimerKind.focus) require(t.shortBreakMinutes in 1..60 && t.longBreakMinutes in 1..60 && state.projects.first { it.id == t.projectID }.status == ProjectStatus.ongoing) { "Invalid active focus session." }
        }
        state.breakOffer?.let { id(it.projectID); require(it.projectID in ids && it.kind != TimerKind.focus && it.minutes in 1..60) { "Invalid pending break." } }
    }
}
