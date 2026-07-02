"""
Cross-check harness (no PostgreSQL required).

What it does
  1. Re-implements sql/03_transform_load_dw.sql in pandas and loads staging + dw into
     SQLite (schemas flattened to prefixes so the SQL files run unmodified
     apart from `CREATE OR REPLACE VIEW` -> `CREATE VIEW`).
  2. Executes the REAL sql/05 (view part), sql/06 and sql/07 files.
  3. Verifies results against independent pandas computations on the raw CSV.

What it does NOT do: execute PostgreSQL-only code (01-04, 08-11, plpgsql). Those run on a
real PostgreSQL in the GitHub Actions workflow, and tests/compare_postgres.py then checks
that PostgreSQL returns the same results as this harness.

Usage: python tests/crosscheck.py [path/to/WB_SE4ALL.csv] [--write-results] [--out DIR]
"""
import argparse, re, sqlite3, pathlib
import numpy as np, pandas as pd

ROOT = pathlib.Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser()
ap.add_argument("csv", nargs="?", default=str(ROOT / "data/raw/WB_SE4ALL.csv"))
ap.add_argument("--write-results", action="store_true")
ap.add_argument("--out", default="results", help="output folder, relative to the repository root")
opts = ap.parse_args()
CSV, WRITE, OUT = pathlib.Path(opts.csv), opts.write_results, ROOT / opts.out
AGG = ["WLD", "SSF", "SAS", "LCN", "NAC"]

raw = pd.read_csv(CSV, dtype=str, keep_default_na=False)
raw.columns = [c.lower() for c in raw.columns]

def fix_mojibake(t):
    if re.search("[\u00c3\u00c2]", t):
        try: return t.encode("latin1").decode("utf8")
        except Exception: return t
    return t

# ---- dimensions (mirror of 03_transform_load_dw.sql) -------------------------------
def keyed(df, col):
    df = df.sort_values(col).reset_index(drop=True); df.insert(0, col.split("_")[0] + "_key", range(1, len(df)+1)); return df
g = raw.groupby("ref_area", as_index=False).agg(area_name=("ref_area_label", "min"))
g["area_name"] = g.area_name.map(fix_mojibake)
g["area_type"] = np.where(g.ref_area.isin(AGG), "aggregate", "country_or_territory")
dim_area = g.rename(columns={"ref_area": "iso3"}).sort_values("iso3").reset_index(drop=True)
dim_area.insert(0, "area_key", range(1, len(dim_area)+1))

ind = raw.groupby("indicator", as_index=False).agg(indicator_name=("indicator_label", "min"), unit_code=("unit_measure", "min"),
        unit_name=("unit_measure_label", "min"), unit_type=("unit_type", "min"), unit_multiplier=("unit_mult", "min"), agg_method=("agg_method", "min"))
ind["indicator_name"] = ind.indicator_name.str.strip().str.replace(r"\s+", " ", regex=True)
ind["unit_multiplier"] = ind.unit_multiplier.astype(int)
theme = {"ACS_ELEC":"Energy access","EGY_CLEAN":"Energy access","EGEN_RNEW":"Renewable energy","FEC_RNEW":"Renewable energy",
         "FCON_RNEW":"Renewable energy","FEC_TOT":"Energy efficiency","INT_LVL":"Energy efficiency","INFLW_IC":"Finance"}
sdg = {"ACS_ELEC":"7.1.1","EGY_CLEAN":"7.1.2","FEC_RNEW":"7.2.1","INT_LVL":"7.3.1","INFLW_IC":"7.a.1","EGEN_RNEW":"7.b.1"}
short = ind.indicator.str.replace("WB_SE4ALL_EG_", "")
ind["theme"] = short.map(theme).fillna("Other"); ind["sdg_indicator"] = short.map(sdg)
dim_indicator = ind.rename(columns={"indicator": "indicator_code"}).sort_values("indicator_code").reset_index(drop=True)
dim_indicator.insert(0, "indicator_key", range(1, len(dim_indicator)+1))

b = raw.groupby("comp_breakdown_1", as_index=False).agg(breakdown_label=("comp_breakdown_1_label", "min"))
b["breakdown_family"] = np.select([b.comp_breakdown_1 == "_Z", b.comp_breakdown_1.str.startswith("WB_SE4ALL_RENEWSRC_"),
                                   b.comp_breakdown_1.str.startswith("WB_SE4ALL_TYPE_")], ["NONE", "RENEWABLE_SOURCE", "ENERGY_USE_TYPE"], "NONE")
dim_breakdown = b.rename(columns={"comp_breakdown_1": "breakdown_code"}).sort_values("breakdown_code").reset_index(drop=True)
dim_breakdown.insert(0, "breakdown_key", range(1, len(dim_breakdown)+1))
dim_urb = raw.groupby("urbanisation", as_index=False).agg(urb_label=("urbanisation_label", "min")).rename(columns={"urbanisation": "urb_code"})
dim_urb.insert(0, "urb_key", range(1, len(dim_urb)+1))
yrs = raw.time_period.astype(int); dim_year = pd.DataFrame({"year": range(yrs.min(), yrs.max()+1)}); dim_year["decade"] = dim_year.year//10*10
dim_status = raw.groupby("obs_status", as_index=False).agg(status_label=("obs_status_label", "min")).rename(columns={"obs_status": "status_code"})

fact = (raw.merge(dim_area[["area_key","iso3"]], left_on="ref_area", right_on="iso3")
           .merge(dim_indicator[["indicator_key","indicator_code"]], left_on="indicator", right_on="indicator_code")
           .merge(dim_breakdown[["breakdown_key","breakdown_code"]], left_on="comp_breakdown_1", right_on="breakdown_code")
           .merge(dim_urb[["urb_key","urb_code"]], left_on="urbanisation", right_on="urb_code"))
fact["year"] = fact.time_period.astype(int)
fact["obs_value"] = pd.to_numeric(fact.obs_value.replace("", np.nan))
fact = fact[["area_key","indicator_key","breakdown_key","urb_key","year","obs_value","obs_status"]].rename(columns={"obs_status":"status_code"})
assert len(fact) == len(raw), "join lost/duplicated rows"
assert fact.duplicated(["indicator_key","area_key","breakdown_key","urb_key","year"]).sum() == 0, "grain violated"
assert ((fact.obs_value.isna()) == (fact.status_code == "O")).all(), "CHECK ck_value_matches_status would fail"

# ---- load into SQLite with PostgreSQL-like schema names ----------------------------
con = sqlite3.connect(":memory:")
con.create_function("chr", 1, chr)
raw_sql = raw.replace("", None)
raw_sql.to_sql("staging_se4all_raw", con, index=False)
for name, df in [("dim_area",dim_area),("dim_indicator",dim_indicator),("dim_breakdown",dim_breakdown),("dim_urbanisation",dim_urb),
                 ("dim_year",dim_year),("dim_obs_status",dim_status),("fact_observation",fact)]:
    df.to_sql("dw_" + name, con, index=False)

def sql_text(name):
    t = (ROOT/"sql"/name).read_text()
    t = re.sub(r"^\\.*$", "", t, flags=re.M)               # psql meta-commands
    t = t.replace("CREATE OR REPLACE VIEW", "CREATE VIEW")
    # SQLite views cannot span attached DBs: flatten  schema.object -> schema_object (harness only)
    return re.sub(r"\b(dw|mart|staging|dq)\.(\w+)", r"\1_\2", t)
con.executescript(sql_text("06_views.sql"))
dq_sql = sql_text("05_data_quality.sql"); con.executescript(dq_sql[:dq_sql.index("CREATE OR REPLACE FUNCTION")])

# ---- run every analytics block ----------------------------------------------------
blocks = re.split(r"^-- @query (\w+)\s*$", sql_text("07_analytics.sql"), flags=re.M)
Q = {blocks[i]: pd.read_sql_query(blocks[i+1].strip().rstrip(";"), con) for i in range(1, len(blocks), 2)}
dq = pd.read_sql_query("SELECT * FROM dq_check_results ORDER BY severity, check_id", con)
print(f"Executed {len(Q)} analytics queries and {len(dq)} DQ rules on {len(raw):,} rows\n"); print(dq.to_string(index=False))
errs = dq[(dq.severity == "ERROR") & (dq.failed_rows > 0)]
assert errs.empty, f"ERROR-level DQ rules failed:\n{errs}"

# ---- independent pandas oracle ----------------------------------------------------
r = pd.read_csv(CSV)
def series(ind, urb="_T", brk="_Z"):
    d = r[(r.INDICATOR == ind) & (r.URBANISATION == urb) & (r.COMP_BREAKDOWN_1 == brk)]
    return d.pivot(index="REF_AREA", columns="TIME_PERIOD", values="OBS_VALUE")
cty = lambda w: w[~w.index.isin(AGG)]
el = series("WB_SE4ALL_EG_ACS_ELEC")

# A01
w = el.loc["WLD"].dropna(); a01 = Q["A01_global_access_trend"].set_index("year")
assert np.allclose(a01.elec_access_pct.values, w.values) and list(a01.index) == list(w.index)
assert np.allclose(a01.yoy_pp.dropna().values, w.diff().dropna().round(2).values, atol=0.011)
# A02
d = (cty(el)[2022] - cty(el)[2000]).dropna().reset_index(); d.columns = ["iso3", "g"]
exp = d.sort_values(["g", "iso3"], ascending=[False, True]).head(10)
assert list(Q["A02_top_access_gainers_2000_2022"].iso3) == list(exp.iso3)
# A03
v = cty(el)[2022].dropna(); bands = pd.cut(v, [-1, 50, 90, 99.5, 101], right=False, labels=["4","3","2","1"]).value_counts()
a03 = Q["A03_access_bands_2022"]
assert dict(zip(a03.band.str[0], a03.countries)) == {k: int(n) for k, n in bands.items() if n > 0} and a03.countries.sum() == len(v)
# A04
u, ru = series("WB_SE4ALL_EG_ACS_ELEC", "URB"), series("WB_SE4ALL_EG_ACS_ELEC", "RUR")
gap = (cty(u)[2022] - cty(ru)[2022]).dropna().reset_index(); gap.columns = ["iso3", "g"]
assert list(Q["A04_urban_rural_gap_2022"].iso3) == list(gap.sort_values(["g","iso3"], ascending=[False,True]).head(15).iso3)
# A06
rs = series("WB_SE4ALL_EG_FEC_RNEW", "_T", "WB_SE4ALL_TYPE_RENEWBLS")
dd = (cty(rs)[2021] - cty(rs)[1990]).dropna().reset_index(); dd.columns = ["iso3", "g"]
a06 = Q["A06_renewable_share_change_1990_2021"]
assert list(a06[a06.direction == "increase"].iso3) == list(dd.sort_values(["g","iso3"], ascending=[False,True]).head(5).iso3)
assert list(a06[a06.direction == "decrease"].iso3) == list(dd.sort_values(["g","iso3"]).head(5).iso3)
# A08
fl = series("WB_SE4ALL_EG_INFLW_IC", "_T", "WB_SE4ALL_RENEWSRC_ALLRENEW")
cum = cty(fl).loc[:, 2000:2022].sum(axis=1, min_count=1).dropna().sort_values(ascending=False)
a08 = Q["A08_top_finance_recipients_2000_2022"]
assert list(a08.iso3) == [c for c in cum.sort_index().sort_values(ascending=False, kind="stable").index[:10]]
assert abs(a08.cum_usd_m.iloc[0] - round(cum.iloc[0])) <= 1 and abs(a08.share_pct.iloc[0] - 100*cum.iloc[0]/cum.sum()) < 0.06
# A05 (aggregates are compared only with each other)
agg22 = el[el.index.isin(AGG)][2022].dropna(); a05 = Q["A05_regional_scorecard_2022"].set_index("iso3")
assert set(a05.index) == set(agg22.index) and np.allclose(a05.loc[agg22.index, "elec_access_pct"], agg22.values)
# A07
cap = series("WB_SE4ALL_EG_EGEN_RNEW", "_T", "WB_SE4ALL_RENEWSRC_ALLRENEW"); top = cty(cap)[2022].dropna().reset_index(); top.columns = ["iso3", "v"]
top = top.sort_values(["v", "iso3"], ascending=[False, True]).head(10); a07 = Q["A07_renewable_capacity_mix_2022"]
assert list(a07.iso3) == list(top.iso3) and np.allclose(a07.renew_capacity_w_pc, top.v.values)
sol = series("WB_SE4ALL_EG_EGEN_RNEW", "_T", "WB_SE4ALL_RENEWSRC_SLRERGY")[2022]
assert np.allclose(a07.solar_pct, (100 * sol.loc[top.iso3].values / top.v.values).round(1), atol=.051)
# A09
f9 = r[(r.INDICATOR == "WB_SE4ALL_EG_INFLW_IC") & (~r.REF_AREA.isin(AGG)) & (r.COMP_BREAKDOWN_1 != "WB_SE4ALL_RENEWSRC_ALLRENEW") & r.OBS_VALUE.notna()].copy()
f9["decade"] = f9.TIME_PERIOD // 10 * 10
g9 = f9.groupby(["decade", "COMP_BREAKDOWN_1_LABEL"]).OBS_VALUE.sum().rename("usd").reset_index()
g9["pct"] = 100 * g9.usd / g9.groupby("decade").usd.transform("sum")
m9 = Q["A09_flows_by_source_and_decade"].merge(g9, left_on=["decade", "breakdown_label"], right_on=["decade", "COMP_BREAKDOWN_1_LABEL"], how="outer")
assert len(m9) == len(g9) == len(Q["A09_flows_by_source_and_decade"]) and np.allclose(m9.usd_m, m9.usd.round(0), atol=1) and np.allclose(m9.pct_of_decade, m9.pct, atol=.06)
# A10
ei = cty(series("WB_SE4ALL_EG_INT_LVL")); ok = ei[(ei[2000] > 0) & (ei[2022] > 0)]
cg = ((ok[2022]/ok[2000])**(1/22) - 1).sort_values(kind="stable")
a10 = Q["A10_energy_intensity_best_improvers"]
assert list(a10.iso3) == list(cg.reset_index().sort_values([0, "REF_AREA"]).REF_AREA[:10])
# A12
cl = series("WB_SE4ALL_EG_EGY_CLEAN"); both = pd.DataFrame({"e": cty(el)[2022], "c": cty(cl)[2022]}).dropna()
sel = both[(both.e >= 90) & (both.c < 50)].assign(g=lambda x: x.e-x.c).reset_index().sort_values(["g","REF_AREA"], ascending=[False,True]).head(15)
assert list(Q["A12_cooking_gap_2022"].iso3) == list(sel.REF_AREA)
# A11 totals
a11 = Q["A11_data_coverage_by_indicator"]; assert a11.observations.sum() == len(raw) and a11.missing_obs.sum() == r.OBS_VALUE.isna().sum()
print("\nAll pandas oracle assertions passed (A01-A12, DQ rules).")

if WRITE:
    out = OUT; (out/"analytics").mkdir(parents=True, exist_ok=True)
    for k, df in Q.items(): df.to_csv(out/"analytics"/f"{k}.csv", index=False)
    dq.to_csv(out/"dq_check_results.csv", index=False)
    pd.read_sql_query("SELECT * FROM mart_v_country_year ORDER BY iso3, year", con).to_csv(out/"country_year.csv", index=False)
    print("results written to", out)
