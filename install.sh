#!/bin/bash
# Install steamos-backups on a SteamOS deck. Everything stays in $HOME —
# survives SteamOS updates (immutable rootfs is never touched, no pacman).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1) rclone: static binary into ./bin (SteamOS doesn't ship it)
if [[ ! -x "$DIR/bin/rclone" ]] && ! command -v rclone >/dev/null; then
    echo "Downloading rclone (static linux/amd64)..."
    mkdir -p "$DIR/bin"
    curl -fsSL -o /tmp/rclone.zip https://downloads.rclone.org/rclone-current-linux-amd64.zip
    bsdtar -x -f /tmp/rclone.zip -C /tmp
    mv /tmp/rclone-*-linux-amd64/rclone "$DIR/bin/rclone"
    chmod +x "$DIR/bin/rclone"
    rm -rf /tmp/rclone.zip /tmp/rclone-*-linux-amd64
fi

# 2) secrets must exist before the timer is worth enabling
if [[ ! -f "$DIR/secrets.env" ]]; then
    echo "ERROR: create $DIR/secrets.env first (see secrets.env.example)" >&2
    exit 1
fi
chmod 600 "$DIR/secrets.env"
chmod +x "$DIR/backup.sh"

# 3) systemd user units (no root needed)
mkdir -p "$HOME/.config/systemd/user"
ln -sf "$DIR/systemd/steamos-backup.service" "$HOME/.config/systemd/user/steamos-backup.service"
ln -sf "$DIR/systemd/steamos-backup.timer" "$HOME/.config/systemd/user/steamos-backup.timer"
systemctl --user daemon-reload
systemctl --user enable --now steamos-backup.timer

echo "Installed. Timer status:"
systemctl --user list-timers steamos-backup.timer --no-pager
echo
echo "Run one now:      systemctl --user start steamos-backup.service"
echo "Watch logs:       journalctl --user -u steamos-backup.service -f"
