# Clock Personal-Team Auto-Renew

This folder is for the native iPad Clock app.

Apple Personal Team provisioning profiles expire 7 days after issuance, so this setup intentionally renews at **5 days** to leave a safety margin.

## What it does

- Runs a lightweight check every 6 hours with a macOS LaunchAgent.
- Does nothing while the current install is younger than 5 days.
- After 5 days, waits until the paired iPad is reachable.
- Rebuilds the Clock Xcode project with automatic signing.
- Reinstalls it with `devicectl`.
- Relaunches the Clock app when possible.
- Retries automatically if the Mac is awake but the iPad is unavailable.

## Requirements before installing the renewer

1. Xcode is installed at `/Applications/Xcode.app`.
2. The Clock native Xcode project exists.
3. The app has been successfully installed manually on the iPad once.
4. Developer Mode is enabled on the iPad.
5. Xcode is signed into Jay's Apple Account / Personal Team.
6. The iPad is paired with the Mac. Later we should enable **Connect via network** so renewals can work without a cable when both devices are reachable.

## Install later

After the first successful manual Clock installation, run:

```bash
cd <this-folder>
chmod +x clock-renew.sh install-renewer.sh
./install-renewer.sh
```

The installer will show paired devices and ask for the iPad identifier.

## Logs

- `~/Library/Logs/ClockAutoRenew.log`
- `~/Library/Logs/ClockAutoRenew.launchd.log`
- `~/Library/Logs/ClockAutoRenew.launchd-error.log`

## Important limitation

The Mac must be awake and the iPad must be reachable (USB or paired network connection) for a renewal to actually install. If it is not reachable, the job keeps retrying on later checks.
