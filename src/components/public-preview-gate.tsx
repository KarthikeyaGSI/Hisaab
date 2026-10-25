'use client';

import {useEffect, useRef, useState, type ReactNode, type KeyboardEvent} from 'react';
import styles from './public-preview-gate.module.css';

const acknowledgementKey = 'hisaab-public-preview-2026-10-26';

export function PublicPreviewGate({children,historicalLocationRecords=812_976,sourceReviewedProjectRecords=0,odishaPhotoLocationDossiers=155,odishaDeepSourceReviews=5}: {children: ReactNode;historicalLocationRecords?:number;sourceReviewedProjectRecords?:number;odishaPhotoLocationDossiers?:number;odishaDeepSourceReviews?:number}) {
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
        <p id="preview-intro"><strong>Hisaab is still under development.</strong> We have collected data for {historicalLocationRecords.toLocaleString('en-IN')} historical location records. This is not a count of verified current assets or unique projects. Our source research spans all 36 states and union territories, but coverage is uneven and counts from different sources overlap. This preview is for exploring records; citizen uploads and submissions are not open yet.</p>
        <p className={styles.count}><strong>{sourceReviewedProjectRecords.toLocaleString('en-IN')} source-reviewed project {sourceReviewedProjectRecords===1?'record is':'records are'} currently published.</strong> Source-reviewed means the project identity and displayed facts match cited records, and the location is labelled at the precision the source supports. Payment, present-day site condition and completion are separate claims.</p>
        <ul>
          <li><strong>A dot needs context.</strong> Historical locations and archived road proposals may differ from today’s sites. They do not establish current condition.</li>
          <li><strong>Payment is not the test for showing a project.</strong> A project can be shown when its identity and the facts presented have enough source evidence to understand it. Payment and completion can remain unknown.</li>
          <li><strong>Each money claim needs its own proof.</strong> A budget, sanction, contract, tender status or bill does not by itself establish that money reached a recipient.</li>
          <li><strong>Read the source with the card.</strong> Open “View source” or “Location and original source” for the record, its date and its limits. Missing records do not establish wrongdoing.</li>
        </ul>
        <p className={styles.count}>Odisha alone has {odishaPhotoLocationDossiers.toLocaleString('en-IN')} PPMS project-linked photo-location dossiers; {odishaDeepSourceReviews.toLocaleString('en-IN')} have received deeper source comparison. These are research records, not independently verified work sites or payment claims.</p>
        <details className={styles.process}>
          <summary>How the evidence process works</summary>
          <ol>
            <li>Collect official records and preserve the original source.</li>
            <li>Match the work’s identifiers and document what the location evidence actually represents.</li>
            <li>Check each displayed claim against its source; keep payment, settlement and completion separate.</li>
            <li>Publish reviewed project evidence with its limits, and investigate corrections.</li>
          </ol>
          <p>Collection and review continue as more records become available. Source coverage is not a percentage of all development across India.</p>
        </details>
        <button ref={enter} type="button" className={styles.enter} onClick={acknowledge}>I understand — explore Hisaab <span aria-hidden="true">→</span></button>
        <small className={styles.footnote}>You can revisit source details through “About the data” on the map.</small>
      </section>
    </div>}
  </>;
}
