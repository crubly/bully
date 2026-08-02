package com.example.bully_client

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "bully/app_icon"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "setIcon" -> {
                    val name = call.argument<String>("name") ?: "default"
                    setLauncherIcon(name)
                    result.success(null)
                }
                "currentIcon" -> result.success(currentLauncherIcon())
                else -> result.notImplemented()
            }
        }
    }

    private fun aliases() = mapOf(
        "default" to ComponentName(packageName, "$packageName.MainActivity"),
        "alt" to ComponentName(packageName, "$packageName.AppIconAlt"),
    )

    private fun setLauncherIcon(name: String) {
        val targets = aliases()
        val chosen = targets[name] ?: targets["default"]!!
        for ((key, component) in targets) {
            val state = if (component == chosen) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            packageManager.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
        }
    }

    private fun currentLauncherIcon(): String {
        val targets = aliases()
        for ((name, component) in targets) {
            val state = packageManager.getComponentEnabledSetting(component)
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) return name
        }
        return "default"
    }
}
