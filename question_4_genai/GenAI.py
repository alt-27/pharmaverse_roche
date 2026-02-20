import os, json, re
import pandas as pd

CSV_PATH = "metadata/adae.csv"
ae = pd.read_csv(CSV_PATH)

# openai key is optional - if not set, we will use a simple keyword matching approach instead of LLM
# openai key instructions found here: https://platform.openai.com/account/api-keys

# schema definition
SCHEMA = {
    "USUBJID": "Unique subject id (RETURN ONLY; do not choose as a filter column)",
    "AETERM":  "Adverse event term (e.g., Headache, Fatigue)",
    "AESOC":   "Body system / System Organ Class (e.g., Skin, Cardiac, Eye disorders)",
    "AESEV":   "Severity / intensity (e.g., MILD, MODERATE, SEVERE)",
    "AEDECOD": "Dictionary-derived term (coded)",
}
MAPPABLE_COLS = list(SCHEMA.keys())
SCHEMA_TEXT = "\n".join([f"- {k}: {v}" for k, v in SCHEMA.items()])


class ClinicalTrialDataAgent:
    def __init__(self, df: pd.DataFrame, schema_text: str):
        self.df = df
        self.schema_text = schema_text
        self.use_llm = bool(os.getenv("OPENAI_API_KEY"))
        self.llm = None
        if self.use_llm:
            try:
                from langchain_openai import ChatOpenAI
                self.llm = ChatOpenAI(model="gpt-5", temperature=0)
            except Exception:
                self.use_llm = False

    def _prompt(self, question: str) -> str:
        # Restrict allowed columns + discourage USUBJID
        return f"""
Return ONLY JSON with keys: target_column, filter_value.

Rules:
- target_column MUST be one of: {MAPPABLE_COLS}
- Do NOT choose USUBJID unless the question explicitly asks to filter by a subject id.
- Prefer:
  - AESEV for severity/intensity (e.g., MILD, MODERATE, SEVERE)
  - AETERM for specific AE terms (e.g., Fatigue, Headache, Erythema)
  - AESOC for body system (e.g., eye, skin, cardiac, general disorders)

Schema:
{self.schema_text}

Question:
{question}
""".strip()

    def parse_question(self, question: str) -> dict:
        # use mock LLM if no API key or if LLM call fails for any reason, to ensure robustness
        raw = self._call_llm(question) if self.use_llm else self._mock_llm(question) 
        m = re.search(r"\{.*\}", raw, flags=re.S)
        obj = json.loads(m.group(0) if m else raw)

        # Ensure only these columns are mappable
        col = str(obj.get("target_column", "")).strip()
        val = str(obj.get("filter_value", "")).strip()

        if col not in MAPPABLE_COLS:
            # fallback to a sensible default rather than crashing
            col = "AETERM"

        # if LLM incorrectly chose USUBJID for generic "subjects who..." questions
        if col == "USUBJID" and not re.search(r"\b(usubjid|subject id)\b", question, re.I):
            col = "AETERM"  # default to term-like filtering

        return {"target_column": col, "filter_value": val}

    def _call_llm(self, question: str) -> str:
        return self.llm.invoke(self._prompt(question)).content.strip()

    def _mock_llm(self, question: str) -> str:
        q = question.lower()
        qtok = set(re.findall(r"[a-z0-9]+", q))

        # avoid selecting USUBJID unless explicitly requested
        cols_to_score = [c for c in MAPPABLE_COLS if c != "USUBJID"]
        best_col, best_score = "AETERM", -1

        for col in cols_to_score:
            desc = SCHEMA[col]
            stok = set(re.findall(r"[a-z0-9]+", (col + " " + desc).lower()))
            score = len(qtok & stok) + (2 if col.lower() in q else 0)
            if score > best_score:
                best_col, best_score = col, score

        vals = self.df[best_col].dropna().astype(str).unique().tolist()
        vals = sorted(vals, key=len, reverse=True)[:5000]
        val = next((v for v in vals if v.lower() in q), "")

        if not val:
            m = re.search(r'"([^"]+)"', question)
            val = m.group(1) if m else " ".join(re.findall(r"[A-Za-z0-9]+", question)[-3:])

        return json.dumps({"target_column": best_col, "filter_value": val})


# Execute with case-insensitive matching and partial match fallback
def execute(df: pd.DataFrame, target_column: str, filter_value: str):
    s = df[target_column].astype(str)
    uniq = set(df[target_column].dropna().astype(str).str.lower().unique())

    mask = s.str.lower().eq(filter_value.lower()) if filter_value.lower() in uniq else \
           s.str.contains(re.escape(filter_value), case=False, na=False)

    usubjids = df.loc[mask, "USUBJID"].dropna().astype(str).unique().tolist()
    return len(usubjids), usubjids


# ---------------------------
# Test Script: Example queries
# ---------------------------
agent = ClinicalTrialDataAgent(ae, SCHEMA_TEXT)

questions = [
    "Give me the subjects who had adverse events of Moderate severity.",
    "Which subjects experienced Headache?",
    "How many subjects have eye disorders?",
    "List the subjects with cardiac disorders."
]

for q in questions:
    parsed = agent.parse_question(q)
    n, ids = execute(ae, parsed["target_column"], parsed["filter_value"])
    print("\nQ:", q)
    print("Parsed:", parsed)
    print("Unique subjects:", n)      # number of unique subjects matching the criteria
    print("USUBJID:", ids)            # list of subject ids matching the criteria