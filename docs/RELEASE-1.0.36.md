# TradePilot 1.0.36.0

Daily Loss Limit renews at 23:30 broker time using trades entered in the new period. Older entries and their later closing results remain in carry-over baskets and are excluded from the renewed allowance. Buy/Sell blocked by a reached limit displays a themed notice with suggestions; no order is sent or settings changed. Position sizing identifies a daily-budget block rather than mislabelling it Below minimum lot.

Analytics PDFs add a performance-at-a-glance summary, plain-language descriptions beneath subheadings, clearer chart explanations and fees-inclusive completed results. Currencies remain separate, incomplete coverage is disclosed and no investment returns or forecasts are invented. The admin guide is updated.

Validation: 246 regression checks passed; MT4 and MT5 compiled with zero errors and warnings. Fresh authenticated FTMO/Goat replies confirmed trading off. Goat's pre-boundary entry was excluded while its current-period result reduced the renewed budget. All nine sample PDF pages were rendered and inspected. Visual reached-limit notification, future boundary rollover and end-to-end execution remain unverified. Existing trades, payments, permissions and copying flags were preserved.
