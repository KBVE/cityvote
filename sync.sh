#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME=${IMAGE_NAME:-myapp}
PORT=${PORT:-4321}

log() {
  printf '[sync] %s\n' "$1"
}

log "Building Docker image '${IMAGE_NAME}'..."
docker build . -t "${IMAGE_NAME}"

log "Ensuring nothing else listens on port ${PORT}..."
PIDS=$(lsof -ti tcp:"${PORT}" || true)
if [[ -n "${PIDS}" ]]; then
  log "Killing processes on port ${PORT}: ${PIDS}"
  # shellcheck disable=SC2001
  echo "${PIDS}" | tr '\n' '\0' | xargs -0 kill -9
else
  log "Port ${PORT} already free."
fi

log "Running Docker image '${IMAGE_NAME}' on port ${PORT}..."
docker run --rm -p "${PORT}:${PORT}" "${IMAGE_NAME}"
