#!/bin/bash
# steamos-backups: sync each job in jobs.d/ to Cloudflare R2 via rclone.
# Runs fine standalone or from the systemd timer. Safe on SteamOS (nothing
# touches the immutable rootfs; everything lives in $HOME).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- credentials / destination ------------------------------------------------
# secrets.env defines R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ENDPOINT, R2_BUCKET
if [[ ! -f "$DIR/secrets.env" ]]; then
    echo "ERROR: $DIR/secrets.env missing (copy secrets.env.example and fill in)" >&2
    exit 1
fi
# shellcheck source=secrets.env.example
source "$DIR/secrets.env"

# Configure rclone entirely via env vars — no rclone.conf needed.
export RCLONE_CONFIG_R2_TYPE=s3
export RCLONE_CONFIG_R2_PROVIDER=Cloudflare
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export RCLONE_CONFIG_R2_ENDPOINT="$R2_ENDPOINT"

# --- rclone binary --------------------------------------------------------------
RCLONE="$DIR/bin/rclone"
[[ -x "$RCLONE" ]] || RCLONE="$(command -v rclone || true)"
if [[ -z "$RCLONE" ]]; then
    echo "ERROR: rclone not found. Run install.sh first." >&2
    exit 1
fi

# --- single-instance lock -------------------------------------------------------
exec 9>"$DIR/.lock"
if ! flock -n 9; then
    echo "Another backup run is in progress; exiting."
    exit 0
fi

# --- wait for network (deck may have just woken up) ------------------------------
for i in $(seq 1 12); do
    if "$RCLONE" lsd "r2:$R2_BUCKET" >/dev/null 2>&1; then
        break
    fi
    if [[ $i -eq 12 ]]; then
        echo "ERROR: cannot reach R2 endpoint after 2 minutes; giving up." >&2
        exit 1
    fi
    sleep 10
done

# --- run jobs --------------------------------------------------------------------
STAMP="$(date +%Y-%m-%d_%H%M%S)"
FAILED=0
shopt -s nullglob
JOBS=("$DIR"/jobs.d/*.job)
if [[ ${#JOBS[@]} -eq 0 ]]; then
    echo "No jobs in $DIR/jobs.d/ — nothing to do."
    exit 0
fi

for jobfile in "${JOBS[@]}"; do
    NAME="" SRC="" EXTRA_ARGS=()
    # shellcheck source=jobs.d/eden.job
    source "$jobfile"
    if [[ -z "$NAME" || -z "$SRC" ]]; then
        echo "SKIP $jobfile: must define NAME and SRC" >&2
        FAILED=1
        continue
    fi
    if [[ ! -d "$SRC" ]]; then
        echo "SKIP $NAME: source $SRC not present (SD card unmounted?)" >&2
        FAILED=1
        continue
    fi

    echo "=== [$NAME] $SRC -> r2:$R2_BUCKET/$NAME/current"
    # Files changed or deleted since the last run are moved into a dated
    # archive/ folder instead of being lost — cheap point-in-time versioning.
    if "$RCLONE" sync "$SRC" "r2:$R2_BUCKET/$NAME/current" \
        --backup-dir "r2:$R2_BUCKET/$NAME/archive/$STAMP" \
        --exclude '.DS_Store' --exclude '._*' \
        --transfers 4 --stats-one-line --stats 30s "${EXTRA_ARGS[@]}"; then
        echo "=== [$NAME] OK"
    else
        echo "=== [$NAME] FAILED" >&2
        FAILED=1
    fi
done

exit $FAILED
