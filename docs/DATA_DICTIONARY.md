# Data dictionary & data-quality findings

## Source profile (full file)
* 144,418 rows × 39 columns; grain = indicator × area × breakdown × urbanisation × year (no duplicates).
* **19 columns are constant** (STRUCTURE, ACTION, FREQ, SEX=`_T`, AGE=`_T`, COMP_BREAKDOWN_2/3, DATABASE_ID, TIME_FORMAT,
  OBS_CONF …) and are dropped in the warehouse.
* 239 areas = **234 countries/territories + 5 aggregates** (`WLD`, `SSF`, `SAS`, `LCN`, `NAC`).
* 8 indicators, 1990-2022 (series differ in coverage - see query A11).

## Warehouse tables
| Table | Grain / purpose |
|---|---|
| `dw.fact_observation` | indicator × area × breakdown × urbanisation × year; `obs_value` NULL ⇔ `status_code='O'` |
| `dw.dim_area` | ISO3 code, name, `area_type` (country_or_territory / aggregate) |
| `dw.dim_indicator` | code, cleaned name, unit, SDG-7 target reference, theme |
| `dw.dim_breakdown` | renewable source (hydro, solar, …) or energy-use type (electricity, heat, transport) |
| `dw.dim_urbanisation` | `_T` total, `URB`, `RUR` |
| `dw.dim_year`, `dw.dim_obs_status` | calendar helper, publisher status flags |

## Indicators
| Code (suffix of `WB_SE4ALL_EG_`) | SDG 7 ref | Unit | Breakdown / notes |
|---|---|---|---|
| `ACS_ELEC` | 7.1.1 | % population | total / urban / rural |
| `EGY_CLEAN` | 7.1.2 | % population | clean fuels & technologies for cooking; total / urban / rural |
| `FEC_RNEW` | 7.2.1 | % of final energy | `RENEWBLS` and `MDRNRENWBLS` (modern) |
| `FCON_RNEW` | - | PJ | renewable consumption by use: electricity / heat / transport |
| `FEC_TOT` | - | PJ | total final energy consumption |
| `INT_LVL` | 7.3.1 | MJ / 2017 PPP $ GDP | energy intensity |
| `INFLW_IC` | 7.a.1 | millions of 2020 USD | international financial **commitments** to developing countries in support of clean energy, by technology. Published label: "International financial flows to developing countries in support of clean energy, International Commitments (2020 USD millions)". These are commitments, not money received or spent. |
| `EGEN_RNEW` | 7.b.1 | W per capita | installed renewable capacity, by technology |

## Cleaning decisions
| # | Issue found | Treatment |
|---|---|---|
| 1 | 19 constant columns | dropped |
| 2 | `Saint-BarthÃ©lemy` (double-encoded UTF-8) | repaired by `staging.fix_mojibake()`; DQ06 guards regression |
| 3 | Double spaces in indicator names | whitespace normalised |
| 4 | 2,512 empty `OBS_VALUE` with status `O` | stored as NULL + status `O` (never imputed); CHECK constraint enforces the pairing |
| 5 | Regional aggregates mixed with countries | `area_type` flag; all country analytics filter on it |
| 6 | `UNIT_MULT = 6` published on `W_PER_C` series | **source metadata anomaly**: values (e.g. Iceland 7,722) are plain W/capita, so the multiplier is *stored but not applied*. USD series (`UNIT_MULT=6`, "USD millions") are consistent |
| 7 | Values carry up to 6 real decimals plus float noise beyond 12 decimals | stored as `NUMERIC(20,8)`. Every real digit is kept and the noise is dropped |

## Empirical consistency rules (all verified on the full file)
| Rule | Result |
|---|---|
| Capacity: all-renewables = Σ sources | max abs diff 2.0 W/capita (rounding) -> tolerance 2.5 |
| Finance: all-renewables = Σ sources incl. "multiple renewables" | max abs diff 0.02 USD m -> tolerance 0.05 |
| Modern renewables ≤ renewables share | 0 violations |
| Percent series ∈ [0,100]; no negatives | 0 violations |
| Σ renewable PJ by use ≈ share × total final energy | median ratio 1.000 (informational) |
| Rural access > urban access | **222 observations** (reported by source; INFO) |
| National total outside [urban, rural] ±0.15 pp | **19 observations** (WARN) |
