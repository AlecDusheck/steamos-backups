# steamos-backups

Daily backups from a Steam Deck (SteamOS, Arch-based, immutable rootfs) to
Cloudflare R2. No pacman, no root — everything lives in `~/steamos-backups`
and a systemd **user** timer, so it survives SteamOS updates.

## Layout

- `backup.sh` — runner: syncs every `jobs.d/*.job` to `r2:<bucket>/<name>/current`,
  moving changed/deleted files to `<name>/archive/<timestamp>/` (versioning).
- `jobs.d/*.job` — one file per directory to back up (`NAME`, `SRC`, optional `EXTRA_ARGS`).
  Add a job by dropping a new `.job` file; disable one by renaming to `.job.disabled`.
- `secrets.env` — R2 credentials (gitignored; see `secrets.env.example`).
- `systemd/` — user service + daily timer (`Persistent=true`, so a missed run
  fires next time the deck is awake).
- `install.sh` — downloads a static rclone into `bin/`, symlinks the units,
  enables the timer.

## Install on the deck

```sh
rsync -a --exclude bin/ ~/steamos-backups/ deck@<deck-ip>:steamos-backups/
ssh deck@<deck-ip> '~/steamos-backups/install.sh'
```

## Ops

```sh
systemctl --user list-timers steamos-backup.timer   # next run
systemctl --user start steamos-backup.service       # run now
journalctl --user -u steamos-backup.service -e      # logs
```

## Restore

```sh
rclone sync r2:<bucket>/eden/current /run/media/mmcblk0p1/Emulation/storage/eden
```
