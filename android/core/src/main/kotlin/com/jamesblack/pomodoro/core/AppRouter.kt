package com.jamesblack.pomodoro.core

import java.net.URI
import java.net.URLDecoder

sealed interface AppRoute {
    data object Timer: AppRoute
    data object NewProject: AppRoute
    data class StartFocus(val projectID: String): AppRoute
    data class CaptureThought(val sessionID: String? = null): AppRoute
    data class PlanNextSession(val projectID: String): AppRoute
}
object AppRouter {
    private fun id(value: String?): String? = value?.takeIf { it.matches(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")) }?.uppercase()
    fun parse(uri: String): AppRoute? = runCatching {
        val u = URI(uri)
        if (!u.scheme.equals("pomodoro", true) || u.userInfo != null || u.port != -1 || u.fragment != null) return null
        val path = u.rawPath ?: ""
        val items = u.rawQuery?.split('&')?.map { item -> val split = item.split('=', limit = 2); URLDecoder.decode(split[0], "UTF-8") to split.getOrNull(1)?.let { URLDecoder.decode(it, "UTF-8") } }
        when (u.host?.lowercase()) {
            "timer" -> if (path.isEmpty() && items == null) AppRoute.Timer else null
            "projects" -> if (path == "/new" && items == null) AppRoute.NewProject else null
            "focus" -> if (path.isEmpty() && items?.size == 2 && items.map { it.first }.toSet() == setOf("project", "action") && items.first { it.first == "action" }.second == "start") id(items.first { it.first == "project" }.second)?.let(AppRoute::StartFocus) else null
            "thoughts" -> if (path != "/new") null else if (items == null) AppRoute.CaptureThought() else if (items.size == 1 && items[0].first == "session") id(items[0].second)?.let { AppRoute.CaptureThought(it) } else null
            "plan" -> if (path == "/next" && items?.size == 1 && items[0].first == "project") id(items[0].second)?.let(AppRoute::PlanNextSession) else null
            else -> null
        }
    }.getOrNull()
    fun url(route: AppRoute): String = when (route) {
        AppRoute.Timer -> "pomodoro://timer"
        AppRoute.NewProject -> "pomodoro://projects/new"
        is AppRoute.StartFocus -> "pomodoro://focus?project=${requireNotNull(id(route.projectID))}&action=start"
        is AppRoute.CaptureThought -> "pomodoro://thoughts/new" + (route.sessionID?.let { "?session=${requireNotNull(id(it))}" } ?: "")
        is AppRoute.PlanNextSession -> "pomodoro://plan/next?project=${requireNotNull(id(route.projectID))}"
    }
}
