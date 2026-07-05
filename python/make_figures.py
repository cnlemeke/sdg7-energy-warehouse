
import argparse, pathlib
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser()
ap.add_argument("--results", default="results", help="folder holding country_year.csv")
ap.add_argument("--figures", default="figures", help="folder for the PNG files")
args = ap.parse_args()
FIG = ROOT / args.figures; FIG.mkdir(parents=True, exist_ok=True)
df = pd.read_csv(ROOT / args.results / "country_year.csv")
plt.rcParams.update({"figure.dpi": 140, "axes.spines.top": False, "axes.spines.right": False, "axes.grid": True, "grid.alpha": .25})

# 1 -- electricity access: world urban/rural/total and regional aggregates
fig, ax = plt.subplots(1, 2, figsize=(12, 4.2))
w = df[df.iso3 == "WLD"].dropna(subset=["elec_access_pct"])
for col, lab in [("elec_access_urban_pct", "Urban"), ("elec_access_pct", "Total"), ("elec_access_rural_pct", "Rural")]:
    ax[0].plot(w.year, w[col], label=lab, lw=2.2 if lab == "Total" else 1.6)
ax[0].set(title="World electricity access (% of population)", ylim=(55, 100)); ax[0].legend()
for iso, lab in [("SSF", "Sub-Saharan Africa"), ("SAS", "South Asia"), ("LCN", "Latin America & Caribbean"), ("NAC", "North America")]:
    d = df[(df.iso3 == iso)].dropna(subset=["elec_access_pct"]); ax[1].plot(d.year, d.elec_access_pct, label=lab)
ax[1].set(title="Regional electricity access (%)", ylim=(20, 101)); ax[1].legend(fontsize=8, loc="center left", bbox_to_anchor=(0.0, 0.35), ncol=2)
fig.tight_layout(); fig.savefig(FIG / "01_electricity_access.png"); plt.close(fig)

# 2 -- access to electricity vs clean cooking, 2022
c = df[(df.year == 2022) & (df.area_type == "country_or_territory")].dropna(subset=["elec_access_pct", "clean_cooking_pct"])
fig, ax = plt.subplots(figsize=(6.4, 5.2))
ax.scatter(c.elec_access_pct, c.clean_cooking_pct, s=22, alpha=.65)
lab = c[(c.elec_access_pct >= 90) & (c.clean_cooking_pct < 30)].sort_values("clean_cooking_pct")
for i, (_, r) in enumerate(lab.iterrows()):  # labels sit in a column on the right, joined to their point by a thin line
    ax.annotate(r.iso3, (r.elec_access_pct, r.clean_cooking_pct), xytext=(106, 6 + 7 * i), textcoords="data", fontsize=7, va="center",
                arrowprops=dict(arrowstyle="-", lw=.5, color="#666"))
ax.set_xlim(right=116); ax.set_xticks(range(0, 101, 20))
r_ = c.elec_access_pct.corr(c.clean_cooking_pct)
ax.set(xlabel="Access to electricity (%)", ylabel="Access to clean cooking (%)", title=f"2022: electricity access vs clean cooking access (r = {r_:.2f}, n = {len(c)})")
ax.title.set_fontsize(9); fig.tight_layout(); fig.savefig(FIG / "02_electricity_vs_cooking.png"); plt.close(fig)

# 3 -- renewable capacity per capita and technology mix, top 12 in 2022
t = df[(df.year == 2022) & (df.area_type == "country_or_territory")].dropna(subset=["renew_capacity_w_pc"]).nlargest(12, "renew_capacity_w_pc").iloc[::-1]
fig, ax = plt.subplots(figsize=(7.5, 4.8)); left = 0 * t.renew_capacity_w_pc
for col, lab in [("hydro_capacity_w_pc", "Hydro"), ("wind_capacity_w_pc", "Wind"), ("solar_capacity_w_pc", "Solar")]:
    ax.barh(t.area_name, t[col].fillna(0), left=left, label=lab); left = left + t[col].fillna(0)
ax.barh(t.area_name, t.renew_capacity_w_pc - left, left=left, label="Other", color="#bbb")
ax.set(xlabel="Installed renewable capacity (W per capita)", title="Top 12 countries and territories, 2022"); ax.legend(); fig.tight_layout()
fig.savefig(FIG / "03_capacity_mix.png"); plt.close(fig)
print("figures written to", FIG)
