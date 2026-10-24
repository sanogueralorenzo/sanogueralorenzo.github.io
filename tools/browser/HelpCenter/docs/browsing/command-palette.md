---
title: Use the command palette
description: Search, navigate, switch tabs, revisit history, search any site or ask an AI assistant, and run Crest commands from one field.
slug: /command-palette
keywords: [command palette, address bar, search, commands, tabs, history, top hit, recent tabs, search providers, site search, AI assistant, Tab, autocomplete, scopes, calculator]
---

# Use the command palette

Click the address display or press **Command-L**. The same palette can resolve a web address, search query, open tab, saved page, history entry, Space, settings page, or Crest command.

## Read the results

The first row is what **Return** does. When one result clearly fits what you typed, it leads as the Top Hit: the address the field is completing, a tab or page you use often whose title or address starts with your text, or the result you chose before for the same text. Otherwise the first row opens the address you typed or searches for it with the Space's search engine, and it always follows a Top Hit.

Below it, the palette lists tabs, pinned and saved tabs, history, actions, and other Spaces from the current Space under their own headers, then search suggestions last. Pages you visit often and recently, and open tabs you used recently, rank higher. A page that is open shows once, as its tab. Set the order, how many results each section shows, and whether results blend into one list in **Settings → Search**.

Before you type, the palette shows **Recent Tabs**, the tabs you used most recently, and a few actions, in the order you set in **Settings → Search**. With Recent Tabs first, **Return** goes straight back to the tab you were on before.

## Complete addresses

As you type the start of a site you've typed or opened before, or one a tab shows, the palette fills in the rest of its address in gray. It completes the site name, without `www.`, and once you type a `/`, the next part of the path. **Return** opens what the field shows. Press **Tab**, **Right Arrow**, or **End** to accept the completion and keep typing, or **Escape** or **Delete** to reject it, which makes **Return** run what you typed.

## Search a site or ask an assistant

Type a provider's shortcut, such as **g** for Google, **ddg** for DuckDuckGo, **yt** for YouTube, **w** for Wikipedia, or **claude**, and press **Tab**. While you type the first word, every provider it names or starts to name shows as a chip under the field, with its shortcut; the first is the one **Tab** chooses, and you can click any of them. Once a provider is chosen, a chip with its icon and color appears beside the field. Type your search and press **Return** to search that provider, or to ask an AI assistant. When what you typed is exactly a shortcut, **Tab** chooses the provider even while the field completes an address. Type `$` before a shortcut, such as `$yt`, and a space to choose the provider without pressing **Tab**. Its suggestions, where it offers them, come only from that provider. Press **Escape**, **Delete** in an empty field, or the chip's close control to leave and keep your text.

Crest offers search engines such as Google, DuckDuckGo, Bing, Brave Search and Startpage; AI assistants such as ChatGPT, Claude and Perplexity; and websites such as YouTube, Wikipedia, GitHub, Reddit and Amazon. Turn providers on or off, change their shortcuts, set their options, choose your default search and the one private windows use, and add your own in **Settings → Search**. Search providers stay on this device.

## Narrow to one kind of result

Type `@tabs`, `@history`, `@saved`, `@actions`, or `@spaces` and press **Space** or **Tab** to list every match of that kind and nothing else. Leave the same way you leave a provider. Turn these off with **@ Filters** in **Settings → Search**.

## Run commands by name

Type a verb or feature name such as "archive," "downloads," "reader," "split," or "copy Markdown." Initials work too, such as "tsv" for Toggle Split View. The palette uses the same command catalog as the Mac menus and shortcut settings, so an action stays discoverable even when it has no key equivalent. Settings pages appear the same way.

Type arithmetic such as `24 * 7` to see the answer; **Return** copies it.

## Keyboard

- **Up** and **Down** arrows, or **Control-N** and **Control-P**, move the selection; **Option-Up** and **Option-Down** jump between sections.
- **Tab** chooses the provider whose shortcut you typed, accepts a completion, or moves to the next result. **Shift-Tab** moves back.
- **Return** runs the selected result. Hold **Command** to open it in a background tab, **Shift-Command** for a new tab, **Shift** for Split View, or **Option** for a Quick Window; the selected row shows where it will open while you hold the keys.
- **Shift-Delete** on a history result removes it from history, and on a result the palette learned, forgets it.
- **Escape** leaves a provider or scope, then rejects a completion, then closes the palette.

## What the palette remembers

The palette learns which result you choose for what you type, so the result you usually pick for "gi" leads next time. It remembers this for each Space on this device only, never syncs it, and never learns in a private window. Clearing a Space's history forgets it too, and **Settings → Search → Clear Learned Choices** forgets everything it learned.

Search suggestions from your search engine are optional, never fetched in a private window, and separate from the tabs, history, and actions the palette finds on your device.
