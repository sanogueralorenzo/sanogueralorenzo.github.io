package com.sanogueralorenzo.voice.overlay

import android.accessibilityservice.AccessibilityService
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo

/** Reads and replaces text in the editable field currently focused outside Voice. */
internal class AccessibilityEditor(
    private val service: AccessibilityService
) {
    fun readText(): String {
        val node = findFocusedEditableNode() ?: return ""
        val text = node.text?.toString().orEmpty().trim()
        if (text.isBlank() || isHintText(node, text)) return ""
        return text
    }

    fun replaceText(text: String): Boolean {
        val node = findFocusedEditableNode() ?: return false
        val setTextArgs = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        val set = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, setTextArgs)
        if (set && text.isNotEmpty()) {
            val selectionArgs = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, text.length)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, text.length)
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selectionArgs)
        }
        return set
    }

    private fun isHintText(node: AccessibilityNodeInfo, text: String): Boolean {
        val showingHintText = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && node.isShowingHintText
        val hintText = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            node.hintText?.toString()
        } else {
            null
        }
        return textRepresentsHint(
            text = text,
            showingHintText = showingHintText,
            hintText = hintText,
            hasEditableContent = { selectionConfirmsEditableContent(node, text.length) }
        )
    }

    private fun selectionConfirmsEditableContent(
        node: AccessibilityNodeInfo,
        textLength: Int
    ): Boolean {
        val originalStart = node.textSelectionStart
        val originalEnd = node.textSelectionEnd
        if (originalStart == textLength && originalEnd == textLength) return true

        val supportsSelection = node.actionList.any { action ->
            action.id == AccessibilityNodeInfo.ACTION_SET_SELECTION
        }
        if (!supportsSelection) return true

        val moveToEndArgs = Bundle().apply {
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, textLength)
            putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, textLength)
        }
        if (!node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, moveToEndArgs)) {
            return false
        }

        val refreshed = node.refresh()
        val reachesReportedTextEnd = !refreshed ||
            (node.textSelectionStart == textLength && node.textSelectionEnd == textLength)

        if (originalStart >= 0 && originalEnd >= 0) {
            val restoreArgs = Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, originalStart)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, originalEnd)
            }
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, restoreArgs)
        }
        return reachesReportedTextEnd
    }

    private fun findFocusedEditableNode(): AccessibilityNodeInfo? {
        val direct = service.rootInActiveWindow
            ?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (direct?.isEditable == true) return direct

        service.windows.forEach { window ->
            val root = window.root ?: return@forEach
            val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (focused?.isEditable == true) return focused
        }
        return null
    }
}
