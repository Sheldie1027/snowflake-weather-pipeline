Rebuilt the AI prompt with a system message (role + rules), a structured user message, temperature 0.3, and max_tokens. Key guard: "use ONLY provided numbers, never invent" — the primary defence against hallucinated weather values.

A/B tested prompt variants against explicit criteria (faithfulness, structure, brevity, consistency) rather than vibes. Tested the hallucination guard with deliberately missing data to confirm the model reports gaps instead of inventing.

Hallucination test surfaced a real bug: inline few-shot examples using REAL city names leaked into output — the model reproduced example figures as if real, and back-filled absent cities. Fixed by (1) fictional example cities + old date so any real city must come from real data, and (2) a system rule to report only cities present in the data, never back-fill. The "missing value -> Not available" guard itself worked correctly.

RAW = Bronze (untouched source). DBT_DEV holds both Silver and Gold: the stg_/int_ views are Silver (cleaned, conformed), the dim_/fct_/mart_ tables are Gold (aggregated, tested, serves the AI). The old STAGING/MARTS schemas are legacy.