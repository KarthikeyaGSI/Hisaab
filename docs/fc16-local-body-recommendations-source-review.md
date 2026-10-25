# Sixteenth Finance Commission local-body grant recommendations

Retrieved 15 October 2026. Private source transcription; no public publication or reuse approval.

## What this source gives Hisaab

Volume II, Annexure 10.5 of the Sixteenth Finance Commission report provides state-wise recommended grants for Rural Local Bodies (RLBs) and Urban Local Bodies (ULBs) for FY2026–27 through FY2030–31. It includes all 28 States and gives an award-period total. Its printed table is in whole ₹ crore. The original report is preserved privately at `data/originals/national-panchayat-finance/16th-finance-commission-volume-2.pdf`; SHA-256 `ed5570ef28276627eeb7c9f4366d865d5594a7121a46cdc7534e222dbd529e23`. The private transcription is `data/acquisition/national-panchayat-finance/16fc-state-local-body-recommendations.json`.

For FY2026–27, the report recommends ₹55,909 crore for RLBs and ₹37,272 crore for ULBs across States. Across the full award period it recommends ₹4,35,236 crore for RLBs and ₹2,90,157 crore for ULBs. These are Finance Commission recommendations, not a record that the full amount was appropriated, released, spent or paid. The Union Budget separately describes ₹1.4 lakh crore as aggregate Finance Commission grants to States for FY2026–27 across local-body and disaster grants; that figure has a broader scope and must not be substituted for the table totals.

The report's state/year rows reconcile exactly to each state award-period total, each annual total and the printed all-state totals. MoPR's 28 July 2026 parliamentary response adds state-wise RLB award-period components: tied, untied and performance grants. These also reconcile for each state and nationally to ₹1,74,094 crore, ₹1,74,094 crore and ₹87,048 crore respectively. That component source is preserved as `data/originals/national-panchayat-finance/pib-16fc-rlb-components-2026-07-28.html`. The reproducible validator is `workers/mopr_16fc_local_body.py`; tests cover the checks and prevent recommendation facts being promoted to payment/publication approval.

## How to represent it

Keep this in a distinct `recommended` measure and split RLB from ULB. Do not call it expenditure, “money spent,” or project funding. The year-by-year RLB/ULB table does not provide a grant-component split by year. The separate MoPR state table reports RLB tied, untied and performance recommendations for the full award period. MoPR's implementation guidance says tied grants target sanitation/solid waste and/or water management; untied grants may serve location-specific needs under the Eleventh Schedule. Those rules still do not establish how much any named work received.

The state-wide recommendation table cannot produce Panchayat project cards. In a separate parliamentary response about Fourteenth Finance Commission performance-grant releases, MoPR says it does not maintain Gram-Panchayat-wise details for that release information. That limitation should not be generalized to every later grant system. The next join must be tested in recipient-state/local-body accounts, eGramSwaraj or state implementation systems, using official activity, voucher and payment identifiers. Keep the recommendation and any later release, utilization, bill and settlement as separate records.

Official references:

- [16th Finance Commission, Volume II, Annexure 10.5](https://www.indiabudget.gov.in/doc/16fcvol2.pdf)
- [Ministry of Panchayati Raj: FC-16 RLB grant composition and implementation guidelines](https://www.pib.gov.in/PressReleasePage.aspx?PRID=2298161&lang=1&reg=3)
- [MoPR parliamentary response on grants to PRIs](https://www.pib.gov.in/PressReleasePage.aspx?PRID=2290508&lang=1&reg=3)
- [Union Budget 2026–27 Finance Commission grant headline](https://www.pib.gov.in/PressReleasePage.aspx?PRID=2221390&lang=1&reg=3)
