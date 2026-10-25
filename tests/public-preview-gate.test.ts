import {describe, expect, it} from 'vitest';
import {renderToStaticMarkup} from 'react-dom/server';
import {createElement} from 'react';
import {PublicPreviewGate} from '../src/components/public-preview-gate';

describe('public preview entry notice', () => {
  it('renders the notice and makes the map inert before hydration or acknowledgement', () => {
    const html = renderToStaticMarkup(createElement(PublicPreviewGate, {children: createElement('main', null, 'Map controls')}));
    expect(html).toContain('<div inert=""><main>Map controls</main></div>');
    expect(html).toContain('role="dialog"');
    expect(html).toContain('aria-modal="true"');
    expect(html).toContain('Coverage is incomplete');
    expect(html).toContain('does not establish payment or completion');
    expect(html).toContain('Historical locations and archived road proposals');
    expect(html).toContain('How the evidence process works');
    expect(html).toContain('I understand — explore Hisaab');
  });
});
