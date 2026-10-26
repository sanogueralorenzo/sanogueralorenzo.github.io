---
title: Let coding agents use Crest
description: Let coding agents on your Mac read and act on tabs in the Spaces you choose, through the Model Context Protocol server Crest includes.
slug: /coding-agents
keywords: [agents, AI, MCP, Model Context Protocol, coding agents, Claude Code, Codex, automation]
---

# Let coding agents use Crest

On Mac, coding agents you run, such as Claude Code or Codex, can use Crest as their browser: list and open tabs, read pages, click and type, take screenshots, and read a page's console and network requests. They work in the Spaces you choose, with the sites you're already signed in to there.

Agents are off until you turn them on.

## Turn on agents

1. Open **Settings > Agents**.
2. Turn on **Allow agents to use Crest**.
3. Under **Spaces**, turn on each Space agents may use.
4. Under **Connect an Agent**, choose **Copy Setup** for your agent, and paste it in your agent's terminal or settings.

Crest must be open while an agent works. Before an agent opens a window, Crest asks you; you can let it open windows without asking until it disconnects, except private windows, which Crest always asks about.

To start Crest without bringing it to the front, a tool can run `open -g --env CREST_BACKGROUND_LAUNCH=1 -a Crest`. Crest opens your windows behind the app you're using, and comes forward only to ask you something, such as about an agent it hasn't met.

## Allow an agent

The first time an agent uses Crest, Crest asks whether to allow it. The question names the program macOS verified by its code signature, not the name the agent gives itself. Crest remembers your answer and lists the agent under **Allowed agents**. Choose **Forget** to disconnect it; Crest asks again the next time it connects.

When the program is a general interpreter, such as node or python, allowing it covers any program it runs under the same agent name.

## See what agents do

- Each tab an agent uses shows the agent's badge and an outline in its colour, and the page shows a bar naming the agent.
- A pointer in the agent's colour shows where it clicks, hovers, fills and scrolls.
- Choose **Stop** in that bar, or **Stop Agent in This Tab** from the badge, to keep the agent out of that tab, through any of its connections, until Crest quits or you forget the agent.
- **Settings > Agents** lists the agents connected now, with what each did lately, such as the tabs it opened and closed. Choose **Disconnect** to end one's connection.
- Choose **Stop All Agents** in the Crest menu, or in **Settings > Agents**, to disconnect every agent and keep agents out of the tabs they used until Crest quits.
- Before an agent deletes history, Crest asks you, naming the agent, the address and the Space.
- Turning agents off disconnects every agent.

## What agents can reach

- Only the Spaces you turned on. A locked Space shows agents its name and nothing in it.
- Never into a private window, even one an agent opened for you, and never Crest's own pages, such as Settings, a browser or extension page, or a file. An agent opens an address in a private window only when it opens a new one.
- History only in the Spaces you turned on, never private history.
- Only `http` and `https` pages, and blank ones.
- Not your saved passwords. A password field's value is left out of what agents read, cookies and sign-in headers are hidden in the requests they read, and request and response bodies are never shown.
- Scripts in a page's own world only when you turn on **Let agents run scripts in pages**. A script runs with the page's own access, so it can read anything the page holds, including a password filled in on it.

Any program that runs as you on your Mac can run an agent you allowed. Crest's question tells agents apart so you can see and control them; it is not a defense against harmful software already on your Mac. Allow only agents you trust, and turn agents off when you don't need them.

## For agent authors

Crest includes a Model Context Protocol server as a helper inside the app, which an agent runs over its standard input and output:

```text
/Applications/Crest.app/Contents/Helpers/crest-browser mcp
```

It speaks protocol version 2026-07-28 and the earlier versions that open with `initialize`. Call `identify` first with your name and brand colour as `#RRGGBB`, so the person sees which tabs you use. Then use `list_spaces` and `list_tabs`, and read pages with `take_snapshot`, whose element `uid`s `click`, `hover`, `fill` and `scroll` take. The other tools are `open_tab`, `navigate`, `show_tab`, `close_tab`, `screenshot`, `type_text`, `press_key`, `wait_for`, `list_console_messages`, `list_network_requests`, `get_network_request`, `evaluate_script`, `read_page_text`, `handle_dialog`, `search_history`, `delete_history`, `list_search_providers`, `open_window`, `open_blank_window`, `open_quick_window` and `open_private_window`.

`read_page_text` answers a page's readable text as Markdown, without any form field's value. `handle_dialog` answers a page's alert, confirm or prompt, but never a question about leaving the page. `wait_for` also takes `url`, to wait until the tab's address contains it. Tools that open a window wait while Crest asks the person.

When a page runs on WebKit, input reaches it as script events, which some pages ignore, and its network requests show their address, type and timing without their method, status or headers.

## Launchers and other tools

Launchers and other local tools use the same helper, approval and Spaces as coding agents.

- `list_spaces` says which Space is active and includes each unlocked Space's artwork. `list_tabs` says whether each tab is pinned or saved and which folders hold it.
- `show_tab` shows the tab itself, opening a normal window over its Space only when none is open. `close_tab` closes only open tabs.
- `search_history` searches the history of the allowed, unlocked Spaces, newest first. Every word of `query` must appear in the title or address, `domain` matches a host and its subdomains, and `limit` takes 1 through 1000, 25 by default.
- `delete_history` removes every visit to one `url`, without its fragment, from one allowed, unlocked `space`, once the person agrees. An address with no visits removes nothing and asks nothing.
- `list_search_providers` lists the enabled search providers and a Space's default.
- `open_window`, `open_blank_window` and `open_quick_window` open a window over an allowed, unlocked Space, at an `http` or `https` address where they take one. `open_private_window` answers only with the window's ID; an address opens only in a new Private Window.
