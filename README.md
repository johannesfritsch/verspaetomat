# Verspätomat

Du bist spät, du spendest. A gamified train check-in app for Germany: delays earn points, delays of 60+ minutes become statutory compensation claims, and the claim names a partner NGO as payee so the railway pays the NGO directly. The app never touches money.

| Folder | What |
|---|---|
| `docs/` | Research, product concept, screens, data requirements, backend architecture. Start at `docs/README.md`. |
| `app/` | Flutter app. Demo mode (built-in data) and local mode (talks to the backend). `app/README.md`. |
| `backend/` | Rust API on Postgres with live train data from Transitous. `backend/README.md`. |

## Run everything locally

```bash
# 1. backend (needs Homebrew postgresql@17 and Rust)
cd backend && ./dev.sh

# 2. app on the iPhone simulator, pointed at the local backend
cd app && flutter run -d "iPhone 15 Pro"
# in the app: Einstellungen → Backend → Lokal
```

All names, stations, amounts and organisations in the demo data are invented.
