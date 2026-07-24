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

## Docker Compose

Create a local environment file first:

```bash
cp .env.example .env
```

Edit `.env` and replace `change-me` with a long random token.

Start the app and nginx:

```bash
docker compose up -d --build
```

The FastAPI app runs inside Docker on port `8000`, and nginx exposes it on
host port `80`.

```bash
curl http://127.0.0.1/health
```

Stop the stack:

```bash
docker compose down
```

Uploaded files are stored on the host under `received_files/`.

## EC2 Docker Deployment

Launch an Ubuntu EC2 instance, then allow these inbound security group rules:

| Type | Port | Source |
| --- | ---: | --- |
| SSH | 22 | Your IP |
| HTTP | 80 | Your IP or lab network |

Do not open port `8000` to the internet.

Install Docker on the EC2 instance:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2 git
sudo usermod -aG docker ubuntu
```

Log out and SSH back in so the Docker group change applies.

Upload or clone this project, then run:

```bash
cd /home/ubuntu/vuln-hospital-booking-c2
cp .env.example .env
nano .env
docker compose up -d --build
```

Check the service:

```bash
docker compose ps
curl http://127.0.0.1/health
curl http://<EC2_PUBLIC_IP>/health
```

View logs:

```bash
docker compose logs -f
```

## Upload Test

```bash
curl -X POST http://127.0.0.1/upload \
  -H "X-Lab-Token: change-me" \
  -F "file=@./sample.txt"
```

Uploaded files are saved under `received_files/` with a random prefix to avoid
overwriting existing artifacts.
