import { escapeHTML, icon } from "../view.js";

export function renderNavigation(state) {
  if (!state.showingNavigation) return "";
  if (state.navigationPage === "search") {
    const query = state.sessionSearch.trim().toLowerCase();
    const messages = state.searchMessages.filter((message) => query && message.text.toLowerCase().includes(query));
    const results = messages.map((message) => `<button class="navigation-search-result" data-action="open-session" data-session="${escapeHTML(message.sessionId)}"><span class="search-result-title">${escapeHTML(message.title || "Side chat")}</span><span class="search-result-message">${escapeHTML(message.text)}</span></button>`).join("");
    const content = state.searchLoading ? '<p class="navigation-no-results">Loading messages…</p>'
      : !query ? `<div class="navigation-search-empty">${icon("search", 30)}<span>Search messages</span></div>`
        : results || '<p class="navigation-no-results">No matching messages</p>';
    return `<section class="chat-search-page"><header class="chat-search-header"><button class="icon-button" data-action="close-search" aria-label="Close search">${icon("back", 19)}</button><strong>Search</strong></header><div class="chat-search-results">${content}</div><label class="chat-search-input">${icon("search", 17)}<input data-focus="chat-search" aria-label="Search messages" type="search" placeholder="Search messages" value="${escapeHTML(state.sessionSearch)}"><button class="icon-button" data-action="close-search" aria-label="Close search">${icon("close", 17)}</button></label></section>`;
  }
  const archived = state.navigationPage === "archived";
  const sideChats = state.navigationPage === "archived"
    ? `<div class="navigation-empty"><span class="navigation-empty-icon">${icon("archive", 30)}</span><strong>Archived chats are here</strong><p>Side chats you archive will show up here.</p></div>`
    : state.sessions.length
    ? state.sessions.map((session) => `<button class="navigation-chat ${session.id === state.selectedSessionId ? "selected" : ""}" data-action="open-session" data-session="${escapeHTML(session.id)}"><span>${escapeHTML(session.title || "Side chat")}</span>${session.activeRunId ? '<i class="spinner"></i>' : ""}</button>`).join("")
    : `<div class="navigation-empty"><span class="navigation-empty-icon">${icon("more", 30)}</span><strong>Start a side chat</strong><p>Side chats are an optional way to organize your conversations by topic.</p></div>`;
  return `<div class="navigation-overlay" data-action="close-navigation"><aside class="navigation-panel" data-menu="navigation" aria-label="Chat navigation">
    <header class="navigation-header"><strong>${archived ? "Archived" : "Agent"}</strong><div class="navigation-header-actions">${!archived ? '<button class="navigation-invite" disabled>Invite</button>' : ""}<button class="icon-button" data-action="${archived ? "navigation-back" : "close-navigation"}" aria-label="${archived ? "Back to chats" : "Close navigation"}">${icon(archived ? "back" : "menu", 19)}</button></div></header>
    ${archived ? `<div class="navigation-content archived-content">${sideChats}</div>` : `<nav class="navigation-sections" aria-label="Chats"><button class="navigation-section ${state.selectedSessionId === "home" ? "selected" : ""}" data-action="navigation-main">${icon("home", 17)}<span>Main chat</span></button><div class="navigation-side-heading"><span>Side chats</span><button class="icon-button archive-button" data-action="navigation-archive" aria-label="Archived chats" title="Archived chats">${icon("archive", 18)}</button></div></nav><div class="navigation-content">${sideChats}</div>`}
    <footer class="navigation-footer"><button class="icon-button" data-action="toggle-settings" aria-label="Settings" title="Settings">${icon("settings", 17)}</button>${archived ? '<span class="navigation-search-placeholder"></span>' : `<button class="navigation-search" data-action="navigation-search">${icon("search", 16)}<span>Search</span></button>`}<button class="icon-button navigation-compose" data-action="new-session" aria-label="New side chat" title="New side chat">${icon("compose", 16)}</button></footer>
  </aside></div>`;
}
