# vuln-hospital-booking-c2

Local lab artifact collector for the vuln-hospital-booking training project.

## Run

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
C2_LAB_TOKEN=change-me python app.py
```

By default, the server binds to `127.0.0.1:8000`. Set `HOST` and `PORT`
explicitly only inside a controlled lab network.

## Upload Test

```bash
curl -X POST http://127.0.0.1:8000/upload \
  -H "X-Lab-Token: change-me" \
  -F "file=@./sample.txt"
```

Uploaded files are saved under `received_files/` with a random prefix to avoid
overwriting existing artifacts.
