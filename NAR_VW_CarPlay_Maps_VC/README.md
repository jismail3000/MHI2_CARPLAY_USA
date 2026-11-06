# NAR_VW_CarPlay_Maps_VC

Based on [MHI2-Carplay-Maps](https://github.com/omonob/MHI2-Carplay-Maps) by **omonob (QCDWJ)**, the original author.

This build has been updated for **North American Volkswagens**, specifically supported MU1126 firmware with NAR 791/891 displays.

CarPlay maps and album artwork for MU1126 firmware and NAR 791/891 displays.
Both display labels use the MU1126/891 payload.

- Runtime version: **US-VCSETTINGS-2.0.1**
- Runtime profile: **MU1126/891+vc-settings**

## Features

- CarPlay maps on the Virtual Cockpit, with steering-wheel map scaling and map switching.
- Saved navigation-card On/Off setting.
- Custom **NAR NavIgnore patch**, adapted for the supported US1126 firmware.
- The CarPlay / Virtual Cockpit settings menu has moved from **App-Connect** to **Navigation -> Settings -> Virtual Cockpit settings**.
- Album artwork with a 150 ms initial settling wait and 1500 ms retry wait.
- The previous validated cover remains visible while the next cover loads or retries; track text updates immediately. A successful new cover replaces it. Disconnect clears the retained cover. Before the first successful cover, the no-picture fallback remains; the cluster frame itself is not removed.

The map view is **800x480**, with navigation-card safe area **(160,60,480,400)**:
left 160, top 60, width 480, height 400. The phone/navigation app renders the card
and determines the available street-name content. No separate percentage scaling
or transparency control for the turn card is included.

## Disclaimer

**Use and install this software entirely at your own risk.** Modifying infotainment software can cause malfunction, data loss, or permanently brick your unit. The original author and contributors to this adapted build accept no responsibility for damage, a bricked unit, or any resulting costs or losses. This software is provided as-is, without warranty. Proceed only if you understand and accept these risks.

## Installation

The MQB Toolbox and access to the Green Engineering Menu must already be available on the unit.

1. Copy this folder's contents to the root of the SD card and insert it into the infotainment unit.
2. Disconnect the phone from CarPlay.
3. Open the **Green Engineering Menu**, then select **MQBCoding** (MQB Toolbox).
4. Select **Update Toolbox** to install the menu and scripts supplied on the SD card.
5. Fully reboot the infotainment unit, then reopen the **Green Engineering Menu -> MQBCoding**. Keep the phone disconnected from CarPlay.
6. Go to **MQBCoding -> Customization -> CarPlay Maps VC**.
7. Select **Install 791/891 NAR** and wait for **CPMAP_INSTALL_OK**.
8. Fully reboot the infotainment unit before reconnecting the phone.
9. In the same Green Engineering Menu page, select **Show installed version/profile** and confirm **US-VCSETTINGS-2.0.1** and **MU1126/891+vc-settings**.
10. Exit the Green Engineering Menu. In the normal infotainment menu, open **Navigation -> Settings -> Virtual Cockpit settings** and check maps, the navigation card, steering-wheel controls and album artwork.

## Saved setup and restore

Before each installation, the installer stages a fresh copy of the currently
installed setup. After a successful installation, that copy replaces the restore
point at `/mnt/app/carplaymaps-vcsettings-before`.

On a first installation, the restore point is the original setup present before
this package was installed.

**Restore saved setup** restores the version present immediately before the latest
successful installation, including its runtime, startup script, CarPlay service
executable and relevant Java files. Disconnect the phone, select **Restore saved
setup**, and fully reboot before reconnecting. Restoring does not swap the two
versions or create a new restore point. Separately stored menu preferences are
retained; this is not a full firmware or graphics backup.

A failed installation retains its pending snapshot for recovery and does not
overwrite the last successful restore point. A retained
pending snapshot must be resolved before another install or restore; recovery
files are not silently deleted. Installation and restore report incomplete
rollback rather than claiming success.

## Troubleshooting

Installer output is appended to `Log/cpmap-vcsettings-install.txt` on writable SD
media, with a RAM-disk fallback. Use **Dump CarPlay Maps VC logs to SD** before
powering off. Exports can contain older logs; use runtime information and uptime
to distinguish sessions because the head-unit calendar clock may be unset.

If installation fails, save the installer log and export the diagnostics before
rebooting. If an incomplete rollback or pending-snapshot error is reported, retain
the recovery files and resolve the error before trying another installation.
Do not reboot when the installer explicitly reports an incomplete rollback.

## Credits and license

Original project: **omonob (QCDWJ)** — [MHI2-Carplay-Maps](https://github.com/omonob/MHI2-Carplay-Maps).
Retain the included `LICENSE` and `COPYING-VC-SETTINGS-GPLv3` files and comply with
their terms when using or redistributing this package.
