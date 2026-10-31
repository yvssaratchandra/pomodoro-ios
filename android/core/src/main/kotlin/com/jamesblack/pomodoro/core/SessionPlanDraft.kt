package com.jamesblack.pomodoro.core

/** An accepted plan. Build candidates first; adopt them only after the complete text saves. */
data class SessionPlanDraft(val rows: List<Row>) {
    constructor(text: String): this(SessionPlanText.items(text).map { Row(text = it) })
    data class Row(val id: String = newID(), val text: String)
    sealed interface Mutation { data class Add(val text: String): Mutation; data class Edit(val id: String, val text: String): Mutation; data class Delete(val id: String): Mutation }
    data class Candidate(val rows: List<Row>, val text: String)
    val characterCount: Int get() = SessionText.count(rows.joinToString("\n") { it.text })
    fun candidate(mutation: Mutation): Candidate {
        val result = rows.toMutableList()
        when (mutation) {
            is Mutation.Add -> { val items = SessionPlanText.items(mutation.text); require(items.isNotEmpty()) { "Enter a task before saving." }; result += items.map { Row(text = it) } }
            is Mutation.Edit -> { val index = result.indexOfFirst { it.id == mutation.id }; require(index >= 0) { "This task is no longer in the session plan." }; val items = SessionPlanText.items(mutation.text); require(items.isNotEmpty()) { "Enter a task before saving." }; result.removeAt(index); result.addAll(index, items.mapIndexed { i, text -> Row(if (i == 0) mutation.id else newID(), text) }) }
            is Mutation.Delete -> { require(result.any { it.id == mutation.id }) { "This task is no longer in the session plan." }; result.removeAll { it.id == mutation.id } }
        }
        return Candidate(result.toList(), SessionPlanText.serialize(result.map { it.text }) ?: "")
    }
    fun adopt(candidate: Candidate): SessionPlanDraft = copy(rows = candidate.rows.toList())
    fun reconcile(text: String): SessionPlanDraft { val available = rows.toMutableList(); return copy(rows = SessionPlanText.items(text).map { value -> val i = available.indexOfFirst { it.text == value }; if (i >= 0) available.removeAt(i) else Row(text = value) }) }
}
sealed interface ThoughtProjectFilter {
    data object All: ThoughtProjectFilter
    data object Unassigned: ThoughtProjectFilter
    data class Project(val id: String): ThoughtProjectFilter
    fun includes(id: String?): Boolean = when (this) { All -> true; Unassigned -> id == null; is Project -> id == this.id }
}
