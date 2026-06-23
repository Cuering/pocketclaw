package com.pocketclaw.pocketclaw

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PocketClawAccessibilityService : AccessibilityService() {

    companion object {
        var instance: PocketClawAccessibilityService? = null
    }

    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openApp" -> {
                val pkg = call.argument<String>("package").orEmpty()
                val launch = packageManager.getLaunchIntentForPackage(pkg)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launch)
                    result.success(ok("Opened $pkg"))
                } else {
                    result.success(fail("App not found: $pkg"))
                }
            }
            // tap and swipe call result.success() themselves (gesture callbacks are async)
            "tap" -> handleTap(call, result)
            "type" -> result.success(handleType(call))
            "scroll" -> result.success(handleScroll(call))
            "swipe" -> handleSwipe(call, result)
            "back" -> {
                val performed = performGlobalAction(GLOBAL_ACTION_BACK)
                result.success(if (performed) ok("Back") else fail("Back failed"))
            }
            "readScreen" -> result.success(handleReadScreen())
            "readClipboard" -> result.success(handleReadClipboard())
            "takeScreenshot" -> handleTakeScreenshot(result)
            else -> result.notImplemented()
        }
    }

    // Always calls result.success() exactly once — either directly or via gesture callback.
    private fun handleTap(call: MethodCall, result: MethodChannel.Result) {
        val selector = call.argument<String>("selector")
        val x = call.argument<Int>("x")
        val y = call.argument<Int>("y")

        if (selector != null) {
            val node = findNode(selector)
            if (node == null) {
                result.success(fail("Element not found: $selector"))
                return
            }
            val performed = node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            node.recycle()
            result.success(if (performed) ok("Tapped $selector") else fail("Tap failed: $selector"))
            return
        }
        if (x != null && y != null) {
            tapAtCoords(x.toFloat(), y.toFloat(), result)
            return
        }
        result.success(fail("tap requires selector or x+y"))
    }

    private fun tapAtCoords(x: Float, y: Float, result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) {
            result.success(fail("Coordinate tap requires Android 7+"))
            return
        }
        val path = Path().apply { moveTo(x, y) }
        val stroke = GestureDescription.StrokeDescription(path, 0L, 50L)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription) {
                result.success(ok("Tapped ($x, $y)"))
            }
            override fun onCancelled(g: GestureDescription) {
                result.success(fail("Tap gesture cancelled"))
            }
        }, null)
    }

    private fun handleType(call: MethodCall): Map<String, Any> {
        val text = call.argument<String>("text").orEmpty()
        val focused = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: return fail("No focused input field")
        val args = Bundle().apply {
            putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                text,
            )
        }
        val performed = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        focused.recycle()
        return if (performed) ok("Typed text") else fail("Type failed — no editable field focused")
    }

    private fun handleScroll(call: MethodCall): Map<String, Any> {
        val direction = call.argument<String>("direction")
            ?: return fail("scroll requires 'direction'")
        val amount = call.argument<Int>("amount") ?: 1
        val root = rootInActiveWindow ?: return fail("No active window")
        val action = when (direction) {
            "down", "right" -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            "up", "left" -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            else -> { root.recycle(); return fail("Unknown direction: $direction") }
        }
        repeat(amount) { root.performAction(action) }
        root.recycle()
        return ok("Scrolled $direction x$amount")
    }

    private fun handleSwipe(call: MethodCall, result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.N) {
            result.success(fail("Swipe requires Android 7+"))
            return
        }
        val fromX = call.argument<Int>("fromX")?.toFloat()
        val fromY = call.argument<Int>("fromY")?.toFloat()
        val toX   = call.argument<Int>("toX")?.toFloat()
        val toY   = call.argument<Int>("toY")?.toFloat()
        if (fromX == null || fromY == null || toX == null || toY == null) {
            result.success(fail("swipe requires fromX, fromY, toX, toY"))
            return
        }
        val path = Path().apply {
            moveTo(fromX, fromY)
            lineTo(toX, toY)
        }
        val stroke = GestureDescription.StrokeDescription(path, 0L, 300L)
        val gesture = GestureDescription.Builder().addStroke(stroke).build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(g: GestureDescription) {
                result.success(ok("Swipe completed"))
            }
            override fun onCancelled(g: GestureDescription) {
                result.success(fail("Swipe cancelled"))
            }
        }, null)
    }

    private fun handleReadScreen(): Map<String, Any> {
        val root = rootInActiveWindow ?: return fail("No active window")
        val sb = StringBuilder()
        serializeNode(root, sb, 0)
        root.recycle()
        return mapOf("ok" to true, "message" to "Screen read", "tree" to sb.toString())
    }

    private fun serializeNode(node: AccessibilityNodeInfo, sb: StringBuilder, depth: Int) {
        val indent = "  ".repeat(depth)
        val className = node.className?.toString()?.substringAfterLast('.') ?: "View"
        val text = node.text?.toString().orEmpty()
        val desc = node.contentDescription?.toString().orEmpty()
        val resId = node.viewIdResourceName?.substringAfterLast('/').orEmpty()
        val label = when {
            text.isNotBlank() -> text
            desc.isNotBlank() -> desc
            resId.isNotBlank() -> "[$resId]"
            else -> ""
        }
        if (label.isNotBlank()) {
            sb.appendLine("$indent$className: $label")
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            serializeNode(child, sb, depth + 1)
            child.recycle()
        }
    }

    private fun handleReadClipboard(): Map<String, Any> {
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
            ?: return fail("Clipboard service unavailable")
        val clip = cm.primaryClip
            ?: return mapOf("ok" to true, "message" to "Clipboard empty", "text" to "")
        val text = clip.getItemAt(0)?.coerceToText(this)?.toString() ?: ""
        return mapOf("ok" to true, "message" to "Clipboard read", "text" to text)
    }

    private fun handleTakeScreenshot(result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.R) {
            result.success(fail("Screenshot requires Android 11+"))
            return
        }
        @Suppress("NewApi")
        takeScreenshot(
            android.view.Display.DEFAULT_DISPLAY,
            mainExecutor,
            object : TakeScreenshotCallback {
                override fun onSuccess(screenshot: ScreenshotResult) {
                    try {
                        val bitmap = Bitmap.wrapHardwareBuffer(
                            screenshot.hardwareBuffer,
                            screenshot.colorSpace,
                        )!!
                        val file = java.io.File(
                            cacheDir,
                            "screenshot_${System.currentTimeMillis()}.png",
                        )
                        java.io.FileOutputStream(file).use { out ->
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                        }
                        bitmap.recycle()
                        screenshot.hardwareBuffer.close()
                        result.success(
                            mapOf("ok" to true, "message" to "Screenshot saved",
                                  "path" to file.absolutePath),
                        )
                    } catch (e: Exception) {
                        result.success(fail("Screenshot encode failed: ${e.message}"))
                    }
                }

                override fun onFailure(errorCode: Int) {
                    result.success(fail("Screenshot failed: $errorCode"))
                }
            },
        )
    }

    private fun findNode(selector: String): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return (root.findAccessibilityNodeInfosByText(selector)?.firstOrNull()
            ?: root.findAccessibilityNodeInfosByViewId(selector)?.firstOrNull())
    }

    private fun ok(message: String): Map<String, Any> =
        mapOf("ok" to true, "message" to message)

    private fun fail(message: String): Map<String, Any> =
        mapOf("ok" to false, "message" to message)
}
