---
title: Use the command palette
description: Search, navigate, switch tabs, revisit history, search the web and run Crest commands from one field.
slug: /command-palette
keywords: [command palette, address bar, search, commands, tabs, history, top hit, recent tabs, Tab, autocomplete, scopes, calculator]
---

# Use the command palette

Click the address display or press **Command-L**. The same palette can resolve a web address, search query, open tab, saved page, history entry, Space, settings page, or Crest command.

## Read the results

The first row is what **Return** does. When one result clearly fits what you typed, it leads as the Top Hit: the address the field is completing, a tab or page you use often whose title or address starts with your text. Otherwise the first row opens the address you typed or searches for it with your chosen provider, and it always follows a Top Hit.

Below it, the palette lists tabs, pinned and saved tabs, history, actions, and other Spaces from the current Space under their own headers, then search suggestions last. Pages you visit often and recently, and open tabs you used recently, rank higher. A page that is open shows once, as its tab.

Before you type, the palette shows **Recent Tabs**, the tabs you used most recently, and a few actions, in a fixed order.  **Return** goes straight back to the tab you were on before.

## Complete addresses

As you type the start of a site in your browsing history or tabs, the palette fills in the rest of its address in gray. It completes the site name, without `www.`, and once you type a `/`, the next part of the path. **Return** opens what the field shows. Press **Tab**, **Right Arrow**, or **End** to accept the completion and keep typing, or **Escape** or **Delete** to reject it, which makes **Return** run what you typed.

## Search the web

Choose Google, DuckDuckGo, Bing, or Brave Search in **Settings → General → Search provider**. Google is the default, and the choice applies to every Space. **Search suggestions**, directly below the provider in General, is off by default. Turn it on to request suggested searches only from that provider; local tab and history results remain available with it off. If it has no supported suggestions endpoint or its request fails, Crest keeps local results without contacting another provider. Suggestions are never requested in private windows.

## Narrow to one kind of result

Type `@tabs`, `@history`, `@saved`, `@actions`, or `@spaces` and press **Space** or **Tab** to list every match of that kind and nothing else. Press **Escape**, **Delete** in an empty field, or the scope chip’s close control to leave.

## Run commands by name

Type a verb or feature name such as "archive," "downloads," "reader," "split," or "copy Markdown." Initials work too, such as "tsv" for Toggle Split View. The palette uses the same command catalog as the Mac menus, so an action stays discoverable even when it has no key equivalent. Settings pages appear the same way.

Type arithmetic such as `24 * 7` to see the answer; **Return** copies it.

## Keyboard

- **Up** and **Down** arrows, or **Control-N** and **Control-P**, move the selection; **Option-Up** and **Option-Down** jump between sections.
- **Tab** accepts a completion, enters a local scope, or moves to the next result. **Shift-Tab** moves back.
- **Return** runs the selected result. Hold **Command** to open it in a background tab, **Shift-Command** for a new tab, or **Shift** for Split View; the selected row shows where it will open while you hold the keys.
- **Shift-Delete** on a history result removes it from history.
- **Escape** leaves a scope, then rejects a completion, then closes the palette.

## History

Local results and address completion use your tabs and the current Space’s browsing history. Clear history to remove its results; saved and open tabs remain available. Crest keeps no separate record of the results you choose for typed text.
