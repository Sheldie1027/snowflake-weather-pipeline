Rebuilt the AI prompt with a system message (role + rules), a structured user message, temperature 0.3, and max_tokens. Key guard: "use ONLY provided numbers, never invent" — the primary defence against hallucinated weather values.

A/B tested prompt variants against explicit criteria (faithfulness, structure, brevity, consistency) rather than vibes. Tested the hallucination guard with deliberately missing data to confirm the model reports gaps instead of inventing.

Hallucination test surfaced a real bug: inline few-shot examples using REAL city names leaked into output — the model reproduced example figures as if real, and back-filled absent cities. Fixed by (1) fictional example cities + old date so any real city must come from real data, and (2) a system rule to report only cities present in the data, never back-fill. The "missing value -> Not available" guard itself worked correctly.

RAW = Bronze (untouched source). DBT_DEV holds both Silver and Gold: the stg_/int_ views are Silver (cleaned, conformed), the dim_/fct_/mart_ tables are Gold (aggregated, tested, serves the AI). The old STAGING/MARTS schemas are legacy.


{
  "overview":  string  - one-sentence summary across all cities
  "cities":    array of {
      "city":         string
      "avg_temp":     number or null
      "air_quality":  string ("Good" | "Moderate" | "Unhealthy" | "Not available")
      "comment":      string - one short sentence
  }
  "alerts":    array of strings - notable conditions worth flagging
}


Numbers drifted between runs on "the same" data. Root cause was the INPUT, not the LLM:
the mart had 129 rows across 43 dates, and the query used LIMIT 40 with no date filter — so ~10 rows per city were sent and the model had to guess which to report. Fixed with QUALIFY row_number() OVER (PARTITION BY city_name ORDER BY reading_date DESC) = 1 to send exactly one latest row per city. 

LIMIT truncates; it does not filter. When LLM output is inconsistent, suspect the input before the model.