# Command Center Dashboard

Single-page, dark-theme command dashboard for MarcusOS.

## Local Build

```bash
cd command-center
./scripts/build-data.sh
python3 -m http.server 8080
```

Open: `http://localhost:8080`

## Sections

- System Health (OpenClaw status, model routing, token spend)
- SkyHawk Pipeline (Salesforce CLI snapshot)
- Venture Tracker (8 MarcusOS ventures)
- Activity Feed (recent system events)
- Implementation Progress (current status)
- Finance tab (YNAB snapshot via `YNAB_API_KEY` from gateway config)

## Data Sources

- OpenClaw: `openclaw status --json` and `~/.openclaw/openclaw.json`
- Salesforce: `sf data query ...` (target org `jason.schaaf@skyhawk.security`)
- YNAB: `https://api.ynab.com/v1` using `YNAB_API_KEY`
- Venture context: `memory/*--Context.md`

When external APIs are unavailable, the dashboard renders degraded status with explicit reasons.

## GitHub Pages

Workflow: `.github/workflows/pages.yml`

After pushing to `main`, Pages deploy URL will be:
`https://jasonschaaf71.github.io/command-center/`
