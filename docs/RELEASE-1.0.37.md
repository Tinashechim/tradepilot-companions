# TradePilot 1.0.37.0

Corrects Percentage daily target previews, provides clearer daily-budget versus broker-margin sizing failures, and shows the requested lot size and checked Required Margin numerically in red when unaffordable. Stop-line changes recalculate sizing; calculated lots display two decimals while execution retains broker-step precision. Status messages fit without overlapping the lots unit, and the Spread OFF Continue/Cancel card stays visible beside the panel. Missing inputs and unavailable broker risk checks give explicit explanations.

Settings adds individual Admin email categories and an Admin opt-out, with a separate all-account automatic-email stop reflecting existing preferences. Manual mail remains available. Checkbox colours are consistent; the admin and installation guides explain the checks and settings.

Validation: 249 regression checks; both native platforms compile with zero errors and warnings. Isolated Settings tests verify independent saves. Native diagnostic logs confirmed MT5 recalculated requested volume as the stop moved; broker free margin was negative, so new entries correctly remained blocked. Final sustained visual checks and end-to-end broker execution remain unverified. Existing trades, payments and trading permissions are preserved.
