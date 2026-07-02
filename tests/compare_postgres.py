"""
Check that PostgreSQL returns the same results as the cross-check harness.

tests/crosscheck.py runs sql/05-07 in SQLite and checks them against pandas. This script
runs the same SQL on a real PostgreSQL and compares:
  * every "-- @query" block in sql/07_analytics.sql
  * the data-quality rules (dq.check_results)
  * the semantic layer (mart.v_country_year)

Usage
  python tests/crosscheck.py data/sample/WB_SE4ALL_sample.csv --write-results --out results/sample/oracle
  python tests/compare_postgres.py results/sample/oracle [--psql "psql -d se4all"]

Connection settings come from the usual PG* environment variables or from --psql.
"""
import argparse, io, pathlib, re, shlex, subprocess, sys
import numpy as np, pandas as pd

ROOT = pathlib.Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser()
ap.add_argument("oracle", help="folder written by crosscheck.py --write-results --out ...")
ap.add_argument("--psql", default="psql", help="psql command, for example: docker compose exec -T db psql -U postgres -d se4all")
opts = ap.parse_args()
ORACLE = pathlib.Path(opts.oracle)
if not ORACLE.is_absolute():
    ORACLE = ROOT / ORACLE
PSQL = shlex.split(opts.psql)


def query(sql):
    """Run one statement on PostgreSQL and return the result as a DataFrame."""
    out = subprocess.run(PSQL + ["-v", "ON_ERROR_STOP=1", "--csv", "-c", sql], capture_output=True, text=True, cwd=ROOT)
    if out.returncode:
        raise SystemExit(f"PostgreSQL error:\n{out.stderr}")
    return pd.read_csv(io.StringIO(out.stdout))


def same(pg, ref, atol):
    """True when shape, columns, text values and numbers (within atol) all agree."""
    if pg.shape != ref.shape or list(pg.columns) != list(ref.columns):
        return False
    for c in pg.columns:
        if pd.api.types.is_numeric_dtype(pg[c]) and pd.api.types.is_numeric_dtype(ref[c]):
            if not np.allclose(pg[c].fillna(-9e9), ref[c].fillna(-9e9), atol=atol, rtol=1e-9):
                return False
        elif not (pg[c].fillna("").astype(str) == ref[c].fillna("").astype(str)).all():
            return False
    return True


failed = []
blocks = re.split(r"^-- @query (\w+)\s*$", (ROOT / "sql/07_analytics.sql").read_text(), flags=re.M)
for i in range(1, len(blocks), 2):
    name = blocks[i]
    pg, ref = query(blocks[i + 1].strip()), pd.read_csv(ORACLE / "analytics" / f"{name}.csv")
    ok = same(pg, ref, atol=0.011)
    print(f"{'MATCH' if ok else 'DIFF ':5s} {name:42s} PostgreSQL rows={len(pg):4d}  oracle rows={len(ref):4d}")
    if not ok:
        failed.append(name)

pg = query("SELECT check_id, severity, description, failed_rows FROM dq.check_results ORDER BY severity, check_id")
ref = pd.read_csv(ORACLE / "dq_check_results.csv")
ok = same(pg, ref, atol=0)
print(f"{'MATCH' if ok else 'DIFF ':5s} {'dq.check_results':42s} PostgreSQL rows={len(pg):4d}  oracle rows={len(ref):4d}")
if not ok:
    failed.append("dq.check_results")

pg = query("SELECT * FROM mart.v_country_year ORDER BY iso3, year")
ref = pd.read_csv(ORACLE / "country_year.csv")
ok = same(pg, ref, atol=1e-6)
print(f"{'MATCH' if ok else 'DIFF ':5s} {'mart.v_country_year':42s} PostgreSQL rows={len(pg):4d}  oracle rows={len(ref):4d}")
if not ok:
    failed.append("mart.v_country_year")

if failed:
    sys.exit(f"\nDifferences found in: {', '.join(failed)}")
print("\nPostgreSQL results equal the pandas-checked results.")
