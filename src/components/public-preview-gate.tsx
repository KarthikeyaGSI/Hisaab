'use client';

import {useEffect, useRef, useState, type ReactNode, type KeyboardEvent} from 'react';
import styles from './public-preview-gate.module.css';

const acknowledgementKey = 'hisaab-public-preview-2026-10-26';

export function PublicPreviewGate({children,assetRecordTotal=812_976,recordsWithAdditionalDetails=812_976}: {children: ReactNode;assetRecordTotal?:number;recordsWithAdditionalDetails?:number}) {
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
        <h1 id="preview-heading">Hisaab is still under development.</h1>
        <p id="preview-intro">Out of {assetRecordTotal.toLocaleString('en-IN')} asset records, {recordsWithAdditionalDetails.toLocaleString('en-IN')} have a location and additional source information.</p>
        <button ref={enter} type="button" className={styles.enter} onClick={acknowledge}>I understand — explore Hisaab <span aria-hidden="true">→</span></button>
      </section>
    </div>}
  </>;
}
