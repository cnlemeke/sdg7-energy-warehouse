# Data sources

## Primary dataset (used by this project)
| Item | Value |
|---|---|
| Dataset | **Sustainable Energy for All (SE4ALL / SDG 7)**, database id `WB_SE4ALL` |
| Publisher | World Bank (Data360 platform) |
| Landing page | https://data360.worldbank.org/en/dataset/WB_SE4ALL |
| File used | `WB_SE4ALL.csv` (SDMX long format, 144,418 rows × 39 columns, 1990-2022, 239 areas) |
| How to get it | Open the landing page -> **Download** -> CSV; save as `data/raw/WB_SE4ALL.csv` |
| Programmatic access | Data360 API base URL `https://data360api.worldbank.org` (see https://github.com/worldbank/data360-mcp for the endpoint conventions) |
| Licence | Creative Commons Attribution 4.0 (CC BY 4.0) - cite the World Bank / SE4ALL |

An alternative, wide-format export of the same SE4ALL database is published through DataBank
(`https://databank.worldbank.org/data/download/SE4ALL_csv.zip`, listed as a CC BY 4.0 resource on
https://energydata.info/dataset/sustainable-energy-for-all). The SQL in this repo targets the
Data360 long format above.

## Optional enrichment datasets (ideas for a later phase, not used yet. Check each URL and licence before use)
| Dataset | Why | Where |
|---|---|---|
| World Development Indicators (population, GDP, region/income-group metadata) | Population-weighted metrics; replace the hard-coded aggregate list with official region/income-group metadata | https://databank.worldbank.org/source/world-development-indicators |
| Our World in Data - Energy dataset | Cross-validation of renewable shares; electricity mix | https://github.com/owid/energy-data |
| Ember yearly electricity data | Generation by source, emissions intensity | https://ember-energy.org/data/ |

Each is open-licensed; check the licence on the download page before redistributing.
