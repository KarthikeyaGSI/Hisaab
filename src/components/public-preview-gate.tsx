'use client';

import {useEffect, useRef, useState, type ReactNode, type KeyboardEvent} from 'react';
import styles from './public-preview-gate.module.css';

const acknowledgementKey = 'hisaab-public-preview-2026-10-25';

export function PublicPreviewGate({children}: {children: ReactNode}) {
  const [acknowledged, setAcknowledged] = useState(false);
  const card = useRef<HTMLElement>(null);
  const enter = useRef<HTMLButtonElement>(null);
  const content = useRef<HTMLDivElement>(null);

  useEffect(() => {
    try {
      if (sessionStorage.getItem(acknowledgementKey) === 'understood') {
        setAcknowledged(true);
        return;
      }
    } catch {}
    enter.current?.focus();
  }, []);

  function acknowledge() {
    try { sessionStorage.setItem(acknowledgementKey, 'understood'); } catch {}
    setAcknowledged(true);
    requestAnimationFrame(() => content.current?.querySelector<HTMLElement>('a, button')?.focus());
  }

  function containFocus(event: KeyboardEvent<HTMLElement>) {
    if (event.key !== 'Tab') return;
    const controls = card.current?.querySelectorAll<HTMLElement>('button, a[href], summary');
    if (!controls?.length) return;
    const first = controls[0], last = controls[controls.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault(); last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault(); first.focus();
    }
  }

  return <>
    <div ref={content} inert={!acknowledged}>{children}</div>
    {!acknowledged && <div className={styles.backdrop}>
      <section ref={card} className={styles.card} role="dialog" aria-modal="true" aria-labelledby="preview-heading" aria-describedby="preview-intro" onKeyDown={containFocus}>
        <span className={styles.label}>HISAAB · PUBLIC PREVIEW</span>
        <h1 id="preview-heading">A clearer picture, built one record at a time.</h1>
        <p id="preview-intro">Hisaab is still collecting and reviewing evidence. Coverage is incomplete, and source dates vary. This map is a starting point for asking better questions. This preview is for exploring records; citizen uploads and submissions are not open yet.</p>
        <ul>
          <li><strong>A dot needs context.</strong> Historical locations and archived road proposals may differ from today’s sites. They do not establish current condition.</li>
          <li><strong>Each stage needs its own proof.</strong> A sanction, contract or reported amount does not establish payment or completion. Missing evidence remains unknown.</li>
          <li><strong>Read the source with the card.</strong> Open “View source” or “Location and original source” for the record, its date and its limits. Missing records do not establish wrongdoing.</li>
        </ul>
        <details className={styles.process}>
          <summary>How the evidence process works</summary>
          <ol>
            <li>Collect official records and preserve the original source.</li>
            <li>Match the work’s identifiers and document the location’s precision.</li>
            <li>Review reuse conditions and check each supported claim separately.</li>
            <li>Publish reviewed evidence with sources, retain gaps, and investigate corrections.</li>
          </ol>
          <p>Collection and review continue as more records become available. Source coverage is not a percentage of all development across India.</p>
        </details>
        <button ref={enter} type="button" className={styles.enter} onClick={acknowledge}>I understand — explore Hisaab <span aria-hidden="true">→</span></button>
        <small className={styles.footnote}>You can revisit source details through “About the data” on the map.</small>
      </section>
    </div>}
  </>;
}
