# Hannyeong website analytics

- Website: https://hannyeong.app/
- GTM: GTM-P7SN2D3S (account 6383508398, container 267627906)
- GA4: G-1856DFR43Z (account 412494027, property 559575242, stream 16160652599)
- Clarity: z095is091v; strict masking, advertising consent denied.

The website loads GTM only after analytics consent. No noscript iframe is installed.
Consent is stored in localStorage (`hannyeong.analytics-consent`). The footer settings
button can change it. Withdrawal stops Clarity, disables GA4, clears first-party
analytics cookies, and reloads to unload vendor listeners. Rejected visits and clicks
are not queued or replayed later.

GTM contains the GA4 destination, a `download_click` event tag, and Clarity.
`gtm-container.json` is the importable configuration used for the initial deployment;
GTM assigns new internal IDs on import. Automatic events and user-provided data
collection are disabled. Download event parameters are `button_location` (`hero`
or `install`), `link_url`, and `link_text`. These indicate clicks, not completed
installation. No app typing data is sent by this website.

Run `node .github/analytics/test-consent.mjs`. After any GTM or consent change, also
verify live network traffic before consent, after acceptance, and after withdrawal.
Never add independently loaded tracking tags that bypass the website consent gate.
