# ENTSO-E PsrType Codes Used In This Repo

This project uses ENTSO-E `PsrType` / `psrType` codes from the Transparency Platform generation documents.

| Code | Meaning |
| --- | --- |
| `B01` | Biomass |
| `B02` | Fossil Brown coal/Lignite |
| `B03` | Fossil Coal-derived gas |
| `B04` | Fossil Gas |
| `B05` | Fossil Hard coal |
| `B06` | Fossil Oil |
| `B07` | Fossil Oil shale |
| `B08` | Fossil Peat |
| `B09` | Geothermal |
| `B10` | Hydro Pumped Storage |
| `B11` | Hydro Run-of-river and poundage |
| `B12` | Hydro Water Reservoir |
| `B13` | Marine |
| `B14` | Nuclear |
| `B15` | Other renewable |
| `B16` | Solar |
| `B17` | Waste |
| `B18` | Wind Offshore |
| `B19` | Wind Onshore |
| `B20` | Other |


## Official References

Primary references used for this repo fix:

- ENTSO-E Transparency Platform `PsrType` guide: https://transparencyplatform.zendesk.com/hc/en-us/articles/15856995130004-PsrType
- ENTSO-E common code lists PDF: https://www.entsoe.eu/Documents/EDI/Library/Core/entso-e-code-list-v36r0.pdf

## Repo Usage Rule

When the project is labeling `psr_type` values from ENTSO-E generation XML, prefer these official `B01`-`B20` names unless the underlying document type explicitly uses a different coding scheme.
