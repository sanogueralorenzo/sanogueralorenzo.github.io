# Jobs

Jobs define schedules or triggers that run actions. Start with systemd timers
or cron, and keep the job itself thin.

## Example systemd timer

`jobs/summarize-repo.timer`

```ini
[Unit]
Description=Daily repo summary

[Timer]
OnCalendar=*-*-* 06:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

`jobs/summarize-repo.service`

```ini
[Unit]
Description=Run repo summary action

[Service]
Type=oneshot
WorkingDirectory=/home/pi/workspaces/my-repo
ExecStart=/home/pi/agent/actions/summarize-repo/run.sh
```

## Conventions

- Keep schedules in `jobs/` and logic in `actions/`.
- Prefer systemd timers over cron on Linux.
