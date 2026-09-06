import { useEffect, useMemo, useRef, useState, type KeyboardEvent } from 'react';
import type { ClipboardItem, ClipboardKind, ClipboardPolicy } from '../contracts.ts';
import type { PaletteBridge } from './PaletteApp.tsx';
import './clipboard.css';

type IconName = 'squares' | 'search' | 'pin' | 'grid' | 'settings' | 'lock' | 'file' | 'image' | 'link' | 'text' | 'back' | 'close';
export function Icon({ name, size = 18 }: { name: IconName; size?: number }) {
  const paths: Record<IconName, React.ReactNode> = {
    squares: <><rect x="3" y="3" width="12" height="12" rx="3" /><rect x="9" y="9" width="12" height="12" rx="3" /></>,
    search: <><circle cx="10.5" cy="10.5" r="6.5" /><path d="m16 16 5 5" /></>,
    pin: <path d="m15 3 6 6-4 1-3 5-5-5 5-3 1-4ZM9 15l-6 6m4-12 8 8" />,
    grid: <><rect x="3" y="3" width="6" height="6" rx="1" /><rect x="15" y="3" width="6" height="6" rx="1" /><rect x="3" y="15" width="6" height="6" rx="1" /><rect x="15" y="15" width="6" height="6" rx="1" /></>,
    settings: <><path d="m9 3-1 3-3 1-2 5 2 5 3 1 1 3h6l1-3 3-1 2-5-2-5-3-1-1-3Z" /><circle cx="12" cy="12" r="3" /></>,
    lock: <><rect x="5" y="10" width="14" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v3" /></>,
    file: <><path d="M14 3H5v18h14V8Zm0 0v5h5" /></>,
    image: <><rect x="3" y="3" width="18" height="18" rx="3" /><circle cx="8" cy="8" r="1" /><path d="m3 17 6-6 4 4 3-3 5 5" /></>,
    link: <><path d="m10 8 3-3a4 4 0 0 1 6 6l-3 3m-2 2-3 3a4 4 0 0 1-6-6l3-3m0 6 8-8" /></>,
    text: <path d="M4 5h16M12 5v15m-4 0h8" />,
    back: <path d="m14 5-7 7 7 7" />,
    close: <path d="m6 6 12 12M6 18 18 6" />,
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}
const kinds: { id: ClipboardKind | 'all'; name: string }[] = [{ id: 'all', name: 'All' }, { id: 'text', name: 'Text' }, { id: 'url', name: 'Links' }, { id: 'image', name: 'Images' }, { id: 'file', name: 'Files' }];
const kindNames = { text: 'Text', url: 'Link', image: 'Image', file: 'File' };
const appName = (item: ClipboardItem) => item.sourceAppName || item.sourceAppId || 'Unknown app';
const appId = (item: ClipboardItem) => item.sourceAppId || 'unknown';
const title = (item: ClipboardItem) => item.title || (item.kind === 'file' ? item.content.split('/').pop() : item.content.split('\n').find((line) => line.trim())) || kindNames[item.kind];
function age(time: number, now: number) {
  const minutes = Math.max(0, Math.floor((now - time) / 60000));
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes} min ago`;
  if (minutes < 1440) return `${Math.floor(minutes / 60)} hr ago`;
  return new Date(time).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}
function AppIcon({ item }: { item: ClipboardItem }) {
  return item.sourceAppIcon ? <img className="clip-app-icon" src={item.sourceAppIcon} alt="" /> : <span className="clip-app-fallback" aria-hidden="true">{appName(item).slice(0, 1).toUpperCase()}</span>;
}
function Thumbnail({ item }: { item: ClipboardItem }) {
  return <span className={`clip-thumbnail ${item.kind}`}>{item.thumbnail ? <img src={item.thumbnail} alt="" /> : <Icon name={item.kind === 'url' ? 'link' : item.kind} size={28} />}</span>;
}

export function ClipboardView({ bridge, onBack }: { bridge: PaletteBridge; onBack: () => void }) {
  const [items, setItems] = useState<ClipboardItem[]>([]);
  const [policy, setPolicy] = useState<ClipboardPolicy>();
  const [query, setQuery] = useState('');
  const [scope, setScope] = useState('all');
  const [kind, setKind] = useState<ClipboardKind | 'all'>('all');
  const [selectedId, setSelectedId] = useState<string>();
  const [loading, setLoading] = useState(true);
  const [historyFailure, setHistoryFailure] = useState('');
  const [feedback, setFeedback] = useState('');
  const [error, setError] = useState(false);
  const [settings, setSettings] = useState(false);
  const [actions, setActions] = useState(false);
  const [busy, setBusy] = useState(false);
  const [scrollTop, setScrollTop] = useState(0);
  const [listHeight, setListHeight] = useState(600);
  const [displayTime, setDisplayTime] = useState(Date.now);
  const input = useRef<HTMLInputElement>(null);
  const list = useRef<HTMLDivElement>(null);
  const operation = useRef(false);
  const refreshVersion = useRef(0);
  const feedbackIsCapture = useRef(false);
  useEffect(() => { if (!actions && !settings) input.current?.focus(); }, [actions, settings]);
  useEffect(() => {
    if (!list.current) return;
    const observer = new ResizeObserver(([entry]) => setListHeight(entry.contentRect.height));
    observer.observe(list.current);
    return () => observer.disconnect();
  }, []);

  function report(message: string, failed = false, capture = false) { feedbackIsCapture.current = capture; setFeedback(message); setError(failed); }
  async function refresh() {
    const version = ++refreshVersion.current;
    try {
      if (!bridge.listClipboard) throw new Error('Clipboard history is unavailable in this host.');
      const next = await bridge.listClipboard('');
      if (version === refreshVersion.current) { setItems(next); setHistoryFailure(''); }
    } catch (failure) {
      if (version === refreshVersion.current) setHistoryFailure(failure instanceof Error ? failure.message : String(failure));
      throw failure;
    }
  }
  useEffect(() => {
    let alive = true;
    let visible = true;
    let refreshing = false;
    const hide = () => { visible = false; };
    const show = () => { visible = true; };
    window.addEventListener("paletteShown", show);
    window.addEventListener("paletteHidden", hide);
    const update = async () => {
      if (operation.current || !visible || refreshing) return;
      refreshing = true;
      try { await refresh(); } catch { /* The current refresh owns its visible error. */ }
      finally {
        refreshing = false;
        if (alive) { setLoading(false); setDisplayTime((previous) => Date.now() - previous >= 60000 ? Date.now() : previous); }
      }
    };
    void update();
    void bridge.getClipboardPolicy?.().then((next) => { if (alive) setPolicy(next); }).catch((failure) => report(failure.message, true));
    const captureError = (event: Event) => report((event as CustomEvent<string>).detail, true, true);
    window.addEventListener('paletteCaptureError', captureError);
    const interval = window.setInterval(update, 2000);
    bridge.setView?.('clipboard');
    input.current?.focus();
    return () => { alive = false; ++refreshVersion.current; window.clearInterval(interval); window.removeEventListener('paletteCaptureError', captureError); window.removeEventListener('paletteHidden', hide); window.removeEventListener('paletteShown', show); };
  }, [bridge]);

  const apps = useMemo(() => {
    const grouped = new Map<string, { item: ClipboardItem; count: number }>();
    for (const item of items) { const id = appId(item); const group = grouped.get(id); if (group) group.count++; else grouped.set(id, { item, count: 1 }); }
    return [...grouped.values()].sort((a, b) => b.count - a.count || appName(a.item).localeCompare(appName(b.item)));
  }, [items]);
  const scoped = useMemo(() => items.filter((item) => (scope === 'all' || (scope === 'pinned' ? item.pinned : appId(item) === scope)) && [item.content, item.title, appName(item)].some((value) => value?.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()))), [items, scope, query]);
  const visible = useMemo(() => scoped.filter((item) => kind === 'all' || item.kind === kind), [scoped, kind]);
  const selected = visible.find((item) => item.id === selectedId) || visible[0];
  const rowHeight = 75;
  const windowStart = Math.max(0, Math.min(visible.length - 1, Math.floor(scrollTop / rowHeight) - 4));
  const windowEnd = Math.min(visible.length, windowStart + Math.ceil(listHeight / rowHeight) + 9);
  const selectedIndex = visible.findIndex((item) => item.id === selected?.id);
  const activeDescendant = selected && selectedIndex >= windowStart && selectedIndex < windowEnd ? `clip-${selected.id}` : undefined;
  useEffect(() => { setSelectedId(undefined); }, [scope, query, kind]);
  function revealRow(index: number) {
    const element = list.current;
    if (!element) return;
    const top = Math.max(0, index) * rowHeight;
    if (top < element.scrollTop) element.scrollTop = top;
    else if (top + rowHeight > element.scrollTop + element.clientHeight) element.scrollTop = top + rowHeight - element.clientHeight;
    setScrollTop(element.scrollTop);
  }
  useEffect(() => {
    if (selected) setSelectedId(selected.id);
    revealRow(selectedIndex);
  }, [selected?.id, scope, query, kind]);

  async function perform(action: () => Promise<void>) {
    if (operation.current) return;
    operation.current = true; setBusy(true); setActions(false); input.current?.focus(); ++refreshVersion.current;
    try { await action(); } catch (failure) { report(failure instanceof Error ? failure.message : String(failure), true); }
    finally { operation.current = false; setBusy(false); }
  }
  function copy(paste = false) {
    if (!selected) return;
    void perform(async () => {
      const restore = paste ? bridge.pasteClipboard : bridge.copyClipboard;
      if (!restore) throw new Error(paste ? 'Direct paste is unavailable. Use Copy instead.' : 'Copy is unavailable.');
      if (!await restore(selected.id)) throw new Error('This clip is no longer available.');
      report(paste ? 'Pasted to the previous app' : 'Copied. Ready to paste.');
    });
  }
  function pin() {
    if (!selected) return;
    void perform(async () => {
      if (!bridge.pinClipboard || !await bridge.pinClipboard(selected.id, !selected.pinned)) throw new Error('Could not update this clip.');
      await refresh(); report(selected.pinned ? 'Clip unpinned' : 'Clip pinned');
    });
  }
  function remove() {
    if (!selected) return;
    const index = visible.findIndex((item) => item.id === selected.id);
    void perform(async () => {
      if (!bridge.removeClipboard || !await bridge.removeClipboard(selected.id)) throw new Error('Could not delete this clip.');
      setSelectedId(visible[index + 1]?.id || visible[index - 1]?.id);
      await refresh(); report('Clip deleted');
    });
  }
  async function savePolicy(next: ClipboardPolicy) {
    if (!bridge.setClipboardPolicy) throw new Error('Clipboard settings are unavailable.');
    await bridge.setClipboardPolicy(next); setPolicy(next); await refresh();
  }
  function navigate(event: KeyboardEvent, delta: number) {
    event.preventDefault();
    const index = Math.max(0, visible.findIndex((item) => item.id === selected?.id));
    const next = Math.max(0, Math.min(visible.length - 1, index + delta));
    setSelectedId(visible[next]?.id);
    revealRow(next);
  }
  function onKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (settings || event.nativeEvent.isComposing) return;
    const modifier = event.metaKey || event.ctrlKey;
    const target = event.target as HTMLElement;
    const editing = target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement || target.isContentEditable;
    const textSelected = !!window.getSelection()?.toString() || (target instanceof HTMLInputElement && target.selectionStart !== target.selectionEnd);
    if (event.key === 'Escape') {
      event.preventDefault();
      if (actions) { setActions(false); input.current?.focus(); }
      else bridge.dismissLauncher?.();
    } else if (modifier && event.key.toLowerCase() === 'f') { event.preventDefault(); input.current?.focus(); }
    else if (modifier && event.key.toLowerCase() === 'k') { event.preventDefault(); setActions((value) => !value); }
    else if (modifier && event.key.toLowerCase() === 'c' && !textSelected) { event.preventDefault(); copy(); }
    else if (modifier && event.key.toLowerCase() === 'p') { event.preventDefault(); pin(); }
    else if (modifier && event.key === 'Backspace' && !editing) { event.preventDefault(); remove(); }
    else if (!editing && event.altKey && event.shiftKey && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
      event.preventDefault(); const scopes = ['all', 'pinned', ...apps.map(({ item }) => appId(item))];
      setScope(scopes[(scopes.indexOf(scope) + (event.key === 'ArrowDown' ? 1 : scopes.length - 1)) % scopes.length]);
    } else if (!editing && event.altKey && event.shiftKey && (event.key === 'ArrowLeft' || event.key === 'ArrowRight')) {
      event.preventDefault(); setKind(kinds[(kinds.findIndex((value) => value.id === kind) + (event.key === 'ArrowRight' ? 1 : kinds.length - 1)) % kinds.length].id);
    } else if (!actions && (target === input.current || target.closest('[role="listbox"]'))) {
      if (target === list.current && event.key === 'Home') navigate(event, -visible.length);
      else if (target === list.current && event.key === 'End') navigate(event, visible.length);
      else if (target === list.current && event.key === 'PageDown') navigate(event, Math.max(1, Math.floor(listHeight / rowHeight)));
      else if (target === list.current && event.key === 'PageUp') navigate(event, -Math.max(1, Math.floor(listHeight / rowHeight)));
      else if (event.key === 'ArrowDown') navigate(event, 1);
      else if (event.key === 'ArrowUp') navigate(event, -1);
      else if (event.key === 'Enter' && (target === input.current || target === list.current)) { event.preventDefault(); copy(true); }
    }
  }

  return <main className="clipboard-shell" onKeyDown={onKeyDown}>
    <header className="clip-header">
      <button className="clip-brand" onClick={onBack} aria-label="Back to Palette launcher"><Icon name="squares" size={25} /><strong>Palette</strong></button>
      <span className="clip-breadcrumb">›</span><span>Clipboard</span>
      <div className="clip-header-actions">
        <button disabled={!policy || busy} onClick={() => policy && void perform(async () => { await savePolicy({ ...policy, enabled: !policy.enabled }); report(policy.enabled ? 'Capture paused' : 'Capture resumed'); })}>{policy?.enabled === false ? '▶ Resume capture' : 'Ⅱ Pause capture'}</button>
        <button className="clip-icon-button" aria-label="Clipboard settings" title="Clipboard settings" disabled={!policy || busy} onClick={() => setSettings(true)}><Icon name="settings" /></button>
      </div>
    </header>
    <div className="clip-search"><Icon name="search" size={20} /><input ref={input} value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search clipboard…" aria-label="Search clipboard" role="combobox" aria-expanded="true" aria-autocomplete="list" aria-controls="clip-results" aria-activedescendant={activeDescendant} autoComplete="off" spellCheck={false} /><kbd>⌘ F</kbd></div>
    <div className="clip-workspace">
      <aside className="clip-sidebar" aria-label="Clipboard sources">
        <nav aria-label="History views"><button className={scope === 'all' ? 'active' : ''} aria-pressed={scope === 'all'} onClick={() => setScope('all')}><Icon name="grid" /><span>All apps</span><small>{!items.length && (loading || historyFailure) ? "—" : items.length}</small></button><button className={scope === 'pinned' ? 'active' : ''} aria-pressed={scope === 'pinned'} onClick={() => setScope('pinned')}><Icon name="pin" /><span>Pinned</span><small>{!items.length && (loading || historyFailure) ? "—" : items.filter((item) => item.pinned).length}</small></button></nav>
        <p className="clip-section-label">Copied from</p>
        <nav className="clip-apps" aria-label="Filter by app">{apps.map(({ item, count }) => <button key={appId(item)} className={scope === appId(item) ? 'active' : ''} aria-pressed={scope === appId(item)} title={appName(item)} onClick={() => setScope(appId(item))}><AppIcon item={item} /><span>{appName(item)}</span><small>{count}</small></button>)}</nav>
        <div className="clip-local"><Icon name="lock" size={15} /><span>Stored on this Mac</span></div>
      </aside>
      <section className="clip-history" aria-label="Clipboard history">
        <div className="clip-types" aria-label="Content types">{kinds.map((filter) => <button key={filter.id} aria-pressed={kind === filter.id} className={kind === filter.id ? 'active' : ''} onClick={() => setKind(filter.id)}>{filter.name}</button>)}</div>
        <div className="clip-results-label"><span>{query ? 'Search results' : scope === 'pinned' ? 'Pinned clips' : 'Recent copies'}</span><small>{!items.length && (loading || historyFailure) ? "—" : visible.length}</small></div>
        <div ref={list} id="clip-results" role="listbox" aria-label="Clipboard items" className="clip-list" tabIndex={0} onScroll={(event) => setScrollTop(event.currentTarget.scrollTop)} aria-activedescendant={activeDescendant}>
          <div aria-hidden="true" style={{ height: windowStart * rowHeight }} />
          {visible.slice(windowStart, windowEnd).map((item, index) => <div key={item.id} id={`clip-${item.id}`} role="option" aria-posinset={windowStart + index + 1} aria-setsize={visible.length} aria-selected={selected?.id === item.id} className={`clip-row ${selected?.id === item.id ? 'selected' : ''}`} onClick={() => { setSelectedId(item.id); list.current?.focus(); }}>
            <Thumbnail item={item} /><div className="clip-row-body"><strong>{title(item)}</strong><span><AppIcon item={item} /><small>{appName(item)} · {age(item.createdAt, displayTime)}</small></span></div><div className="clip-row-end">{item.pinned && <Icon name="pin" size={13} />}<small>{kindNames[item.kind]}</small></div>
          </div>)}
          <div aria-hidden="true" style={{ height: Math.max(0, visible.length - windowEnd) * rowHeight }} />
          {!visible.length && <div className="clip-empty"><Icon name="squares" size={34} /><strong>{historyFailure ? 'History unavailable' : loading ? 'Loading clipboard…' : items.length ? 'No matching clips' : policy?.enabled === false ? 'Capture is paused' : 'Your next copy starts here'}</strong><p>{historyFailure ? 'Clipboard history could not be loaded.' : items.length ? 'Try another app, type, or search.' : 'Copy text, a link, an image, or a file in another app.'}</p>{!!items.length && <button onClick={() => { setQuery(''); setKind('all'); setScope('all'); }}>Clear filters</button>}</div>}
        </div>
      </section>
      <section className="clip-preview" aria-label="Selected clip preview">
        {selected ? <><div className="clip-preview-heading"><h1>{title(selected)}</h1><button className="clip-icon-button" aria-label={selected.pinned ? 'Unpin clip' : 'Pin clip'} aria-pressed={selected.pinned} disabled={busy} onClick={pin}><Icon name="pin" /></button><button className="clip-icon-button" aria-label="Clip actions" aria-expanded={actions} onClick={() => setActions((value) => !value)}>•••</button></div>
          <div className={`clip-content ${selected.kind}`} tabIndex={0}>
            {selected.kind === 'image' && selected.thumbnail ? <img src={selected.thumbnail} alt={title(selected)} /> : selected.kind === 'file' ? <div className="clip-file-preview"><Icon name="file" size={54} /><strong>{title(selected)}</strong><p>{selected.content}</p></div> : <>{selected.kind === 'url' && <Icon name="link" size={32} />}<pre>{selected.content}</pre></>}
          </div>
          <dl className="clip-metadata"><dt>Copied from</dt><dd><AppIcon item={selected} />{appName(selected)}</dd><dt>Type</dt><dd>{kindNames[selected.kind]}</dd>{selected.width && selected.height ? <><dt>Dimensions</dt><dd>{selected.width} × {selected.height}</dd></> : null}<dt>Copied</dt><dd>{new Date(selected.createdAt).toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}</dd></dl>
          <div className="clip-primary-actions"><button className="clip-primary" onClick={() => copy(true)} disabled={busy}>Paste to previous app <kbd>↵</kbd></button><button onClick={() => copy()} disabled={busy}>Copy <kbd>⌘ C</kbd></button></div>
        </> : <div className="clip-empty"><Icon name="image" size={38} /><p>Select a clip to preview it.</p></div>}
      </section>
    </div>
    {historyFailure && <div className="clip-feedback error" role="alert"><span>{historyFailure}</span></div>}
    {feedback && <div className={`clip-feedback ${error ? 'error' : ''}`} role={error ? 'alert' : 'status'}><span>{feedback}</span><button aria-label="Dismiss message" onClick={() => { setFeedback(''); if (feedbackIsCapture.current) bridge.clearCaptureError?.(); feedbackIsCapture.current = false; }}><Icon name="close" size={14} /></button></div>}
    <footer className="clip-footer"><span><kbd>↑ ↓</kbd> Navigate</span><span><kbd>↵</kbd> Paste</span><span><kbd>⌘ C</kbd> Copy</span><button onClick={() => setActions((value) => !value)}><kbd>⌘ K</kbd> Actions</button><span className="clip-footer-end"><kbd>esc</kbd> Close</span></footer>
    {actions && <ActionsDialog onClose={() => { setActions(false); input.current?.focus(); }}><p>Clip actions</p><button autoFocus disabled={!selected || busy} onClick={() => copy(true)}>Paste to previous app <kbd>↵</kbd></button><button disabled={!selected || busy} onClick={() => copy()}>Copy <kbd>⌘ C</kbd></button><button disabled={!selected || busy} onClick={pin}>{selected?.pinned ? 'Unpin clip' : 'Pin clip'} <kbd>⌘ P</kbd></button><button className="danger" disabled={!selected || busy} onClick={remove}>Delete clip <kbd>⌘ ⌫</kbd></button><div className="clip-shortcut-help">With the list focused:<br />⌥ ⇧ ↑ ↓ Switch app<br />⌥ ⇧ ← → Switch type</div><button onClick={() => { setActions(false); input.current?.focus(); }}>Close actions <kbd>esc</kbd></button></ActionsDialog>}
    {settings && <ClipboardSettings policy={policy} apps={apps.map(({ item }) => item)} onClose={() => { setSettings(false); input.current?.focus(); }} onSave={savePolicy} />}
  </main>;
}

function ClipboardSettings({ policy, apps, onClose, onSave }: { policy?: ClipboardPolicy; apps: ClipboardItem[]; onClose: () => void; onSave: (policy: ClipboardPolicy) => Promise<void> }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [draft, setDraft] = useState(policy);
  const [excluded, setExcluded] = useState(policy?.excludedAppIds.join('\n') || '');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);
  useEffect(() => { const modal = dialog.current; modal?.showModal(); return () => modal?.close(); }, []);
  return <dialog ref={dialog} className="clip-settings" onCancel={(event) => { event.preventDefault(); if (!saving) onClose(); }} aria-labelledby="settings-title"><form onSubmit={(event) => { event.preventDefault(); if (!draft || saving) return; setSaving(true); void onSave({ ...draft, excludedAppIds: [...new Set(excluded.split(/[\n,]/).map((id) => id.trim()).filter(Boolean))] }).then(onClose).catch((failure) => setError(failure.message)).finally(() => setSaving(false)); }}><div className="clip-preview-heading"><h1 id="settings-title">Clipboard settings</h1><button type="button" aria-label="Close settings" disabled={saving} onClick={onClose}><Icon name="close" /></button></div>{draft ? <><label className="clip-toggle"><input type="checkbox" checked={draft.enabled} onChange={(event) => setDraft({ ...draft, enabled: event.target.checked })} />Capture clipboard history</label><label>Keep history for<select value={draft.retentionDays ?? 'forever'} onChange={(event) => setDraft({ ...draft, retentionDays: event.target.value === 'forever' ? null : Number(event.target.value) })}>{[1, 7, 30, 90].map((days) => <option key={days} value={days}>{days} days</option>)}{draft.retentionDays !== null && ![1, 7, 30, 90].includes(draft.retentionDays) && <option value={draft.retentionDays}>{draft.retentionDays} days</option>}<option value="forever">Until capacity is reached</option></select></label><label>Maximum clips<input type="number" min="0" max="10000" required value={draft.maxItems} onChange={(event) => setDraft({ ...draft, maxItems: Number(event.target.value) })} /></label><p className="clip-settings-note">Pinned clips are kept until you unpin or delete them. Reducing retention or capacity removes older unpinned clips.</p><label className="clip-toggle"><input type="checkbox" checked={draft.ignoreSensitive} onChange={(event) => setDraft({ ...draft, ignoreSensitive: event.target.checked })} />Skip sensitive content</label><label>Excluded apps<textarea rows={3} value={excluded} onChange={(event) => setExcluded(event.target.value)} placeholder="com.example.App" spellCheck={false} /></label><p className="clip-settings-note">One app identifier per line. Exclusions affect future copies.</p>{apps.filter((item) => item.sourceAppId).length > 0 && <select aria-label="Add an excluded app" value="" onChange={(event) => { if (event.target.value) setExcluded((value) => `${value}\n${event.target.value}`.trim()); }}><option value="">Add an app from history…</option>{apps.filter((item) => item.sourceAppId).map((item) => <option key={item.sourceAppId} value={item.sourceAppId}>{appName(item)}</option>)}</select>}<div className="clip-settings-note"><Icon name="lock" size={14} /> History and image previews are encrypted on this Mac.</div></> : <p>Clipboard settings could not be loaded. Close this panel and try again.</p>}{error && <p role="alert" className="danger">{error}</p>}<div className="clip-settings-actions"><button type="button" onClick={onClose} disabled={saving}>Cancel</button><button className="clip-primary" disabled={!draft || saving}>{saving ? 'Saving…' : 'Save settings'}</button></div></form></dialog>;
}

function ActionsDialog({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  useEffect(() => { const modal = dialog.current; modal?.showModal(); return () => modal?.close(); }, []);
  return <dialog ref={dialog} className="clip-actions" aria-label="Clip actions" onCancel={(event) => { event.preventDefault(); onClose(); }}>{children}</dialog>;
}
