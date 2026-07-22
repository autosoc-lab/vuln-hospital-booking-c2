import os
import re
import secrets
import logging
from pathlib import Path
from uuid import uuid4

import uvicorn
from fastapi import FastAPI, File, Header, HTTPException, UploadFile, status

app = FastAPI()

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("artifact-collector")

UPLOAD_DIR = Path(os.getenv("UPLOAD_DIR", "received_files")).resolve()
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

API_TOKEN = os.getenv("C2_LAB_TOKEN", "dev-only-token")
MAX_FILE_SIZE = int(os.getenv("MAX_FILE_SIZE", str(5 * 1024 * 1024)))
CHUNK_SIZE = 1024 * 1024
SAFE_FILENAME_RE = re.compile(r"[^A-Za-z0-9._-]+")


def sanitize_filename(filename: str | None) -> str:
    basename = Path(filename or "unnamed").name
    sanitized = SAFE_FILENAME_RE.sub("_", basename).strip("._")
    return sanitized or "unnamed"


def require_lab_token(x_lab_token: str | None) -> None:
    if not x_lab_token or not secrets.compare_digest(x_lab_token, API_TOKEN):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="인증 토큰이 올바르지 않습니다.",
        )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/upload")
def receive_file(
    file: UploadFile = File(...),
    x_lab_token: str | None = Header(default=None),
    content_length: int | None = Header(default=None),
):
    require_lab_token(x_lab_token)

    if content_length and content_length > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="파일 크기 제한을 초과했습니다.",
        )

    original_name = sanitize_filename(file.filename)
    saved_name = f"{uuid4().hex}_{original_name}"
    file_path = (UPLOAD_DIR / saved_name).resolve()

    if not str(file_path).startswith(str(UPLOAD_DIR) + os.sep):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="저장 경로가 올바르지 않습니다.",
        )

    written = 0
    try:
        with open(file_path, "wb") as buffer:
            while chunk := file.file.read(CHUNK_SIZE):
                written += len(chunk)
                if written > MAX_FILE_SIZE:
                    buffer.close()
                    file_path.unlink(missing_ok=True)
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail="파일 크기 제한을 초과했습니다.",
                    )
                buffer.write(chunk)

        logger.info(
            "lab artifact received original=%s saved=%s size=%d",
            original_name,
            saved_name,
            written,
        )
        return {
            "status": "success",
            "saved_as": saved_name,
            "original_name": original_name,
            "size": written,
        }

    except HTTPException:
        raise
    except Exception as e:
        file_path.unlink(missing_ok=True)
        logger.exception("failed to save uploaded artifact: %s", e)
        raise HTTPException(status_code=500, detail="파일 저장에 실패했습니다.")


if __name__ == "__main__":
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host=host, port=port)
