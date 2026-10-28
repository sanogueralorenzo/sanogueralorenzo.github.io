import React, {useMemo, useState} from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import {usePluginData} from '@docusaurus/useGlobalData';

export default function HelpSearch() {
  const entries = usePluginData('help-search-index');
  const guideBase = useBaseUrl('/');
  const [query, setQuery] = useState('');
  const normalizedQuery = query.trim().toLocaleLowerCase();
  const results = useMemo(() => {
    if (!normalizedQuery) return [];
    return entries
      .map((entry) => {
        const title = entry.title.toLocaleLowerCase();
        const haystack = [entry.title, entry.description, ...entry.keywords, entry.text]
          .join(' ')
          .toLocaleLowerCase();
        const score = title.includes(normalizedQuery) ? 0 : haystack.includes(normalizedQuery) ? 1 : 2;
        return {...entry, score};
      })
      .filter((entry) => entry.score < 2 && entry.slug !== '/')
      .sort((left, right) => left.score - right.score || left.title.localeCompare(right.title))
      .slice(0, 8);
  }, [entries, normalizedQuery]);

  return (
    <section className="help-search" aria-labelledby="help-search-label">
      <label id="help-search-label" htmlFor="help-search-input">Search</label>
      <div className="help-search-field">
        <span aria-hidden="true">⌕</span>
        <input
          id="help-search-input"
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search articles"
          autoComplete="off"
          aria-describedby="help-search-status"
        />
      </div>
      <p id="help-search-status" className="help-search-status" aria-live="polite">
        {normalizedQuery ? `${results.length} ${results.length === 1 ? 'article' : 'articles'}` : ''}
      </p>
      {normalizedQuery && (
        <div className="help-search-results" role="list">
          {results.map((entry) => (
            <div key={entry.slug} role="listitem">
              <Link to={`${guideBase}${entry.slug.replace(/^\//, '')}`}>
                <strong>{entry.title}</strong>
                <span>{entry.description}</span>
              </Link>
            </div>
          ))}
          {results.length === 0 && (
            <p className="help-search-empty">No matching articles.</p>
          )}
        </div>
      )}
    </section>
  );
}
