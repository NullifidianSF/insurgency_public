# Insurgency 2014 – LGSM cron helpers + SM plugins

This folder contains a small setup that works together to:

- Mark when your **Insurgency 2014** server is *truly* empty.
- Safely **restart the server only when it’s empty**.
- Randomise the **startup map** via your `coop_custom.txt`.
- Play nicely with **`sv_hibernate_when_empty`** (delayed hibernate).

Everything is designed around:

- An **LGSM** Insurgency server (`insserver`) running under a **dedicated Linux user** (placeholder: `USERNAME`).
- A server directory structure like:
  - `/home/USERNAME/insserver` (LGSM script)
  - `/home/USERNAME/serverfiles/insurgency/...`
  - `/home/USERNAME/lgsm/config-lgsm/insserver/insserver.cfg`

> 🔁 Everywhere you see `USERNAME` in scripts or in this README,  
> replace it with the Linux user that actually owns your server (e.g. `user_1`).

---

## Files in this folder

### SourceMod plugins

- `bm_emptyflag.sp` – **Empty Restart Flag**
- `bm_hibernate_delay.sp` – **Hibernate Delay**

### Shell scripts

- `empty_restart.sh` – restart LGSM server if the “server empty” flag is set
- `rotate_defaultmap.sh` – pick a random map from `coop_custom.txt` and write it to `insserver.cfg`’s `defaultmap="..."`

### Cron template

- `cron jobs.txt` – example `crontab` entries that tie everything together: monitor, rotate default map, restart when empty

You’ll also need a **mapcycle file**, for example:

- `/home/USERNAME/serverfiles/insurgency/coop_custom.txt` – one `mapname checkpoint` per line; comments allowed with `//`, `#` or `;`.

---

## How the system works (high level)

1. `bm_emptyflag.smx` watches real humans joining/leaving:
   - If at least one **human** is in game → flag file contains `"0"`.
   - If **no humans** are in game → flag file contains `"1"`.
   - Flag file path (inside the game server tree):  
     `addons/sourcemod/data/bm_server_empty.txt`.

2. `bm_hibernate_delay.smx` controls `sv_hibernate_when_empty`:
   - Disables hibernate when humans are around.
   - When the last human leaves, it **waits `HIBERNATE_DELAY_SEC` seconds**.
   - If the server is **still empty after that delay**, it re-enables hibernate so the engine can sleep.

3. `rotate_defaultmap.sh`:
   - Reads `coop_custom.txt`, ignoring commented/empty lines.
   - Picks a random line like:  
     `ministry_coop checkpoint`
   - Writes that into LGSM config, updating:  
     `defaultmap="ministry_coop checkpoint"` in `insserver.cfg`.

4. `empty_restart.sh` (called from cron):
   - Checks the flag file.
   - If it exists and contains exactly `"1"`, it runs:  
     `/home/USERNAME/insserver restart` via LGSM.

5. `cron jobs.txt` gives you an example crontab:
   - Runs `insserver monitor` every 5 minutes (auto-start if down).
   - Runs `rotate_defaultmap.sh` at 03:00.
   - Runs `empty_restart.sh` at 04:00.

So, once per day (or whatever schedule you set), your server:

- Picks a new random startup map.
- If it’s empty at the scheduled time, it restarts cleanly onto that new map.
- If players are online, it does **not** restart.

---

## 1. Installing the SourceMod plugins

### Prerequisites

- A working **SourceMod** install on your Insurgency server.
- Access to `addons/sourcemod/scripting` and `addons/sourcemod/plugins`.

### 1.1 `bm_emptyflag.sp` – Empty Restart Flag

**What it does:**

- On map start and whenever human players join/leave, it counts **real humans**.
- Writes a tiny text file:
  - Path (inside server dir):  
    `addons/sourcemod/data/bm_server_empty.txt`
  - Content is always exactly:
    - `"1"` → server truly empty (safe to restart).
    - `"0"` → at least one human is in game.
- On plugin unload it deletes the flag file so cron won’t think the server is permanently empty.

**Install:**

1. Copy `bm_emptyflag.sp` into:
   ```text
   /home/USERNAME/serverfiles/insurgency/addons/sourcemod/scripting/
   ```
2. Compile it (on the server or locally), e.g.:
   ```bash
   cd /home/USERNAME/serverfiles/insurgency/addons/sourcemod/scripting
   ./compile.sh bm_emptyflag.sp
   ```
3. Copy the compiled `bm_emptyflag.smx` from `scripting/compiled/` to:
   ```text
   addons/sourcemod/plugins/
   ```
4. Change map or restart the server to load the plugin.

No cvars to configure; it just works.

---

### 1.2 `bm_hibernate_delay.sp` – Hibernate Delay

**What it does:**

- Hooks the `sv_hibernate_when_empty` ConVar.
- On each map start:
  - Forces `sv_hibernate_when_empty 0` so the server doesn’t immediately hibernate.
  - If the server booted empty, it schedules a delayed enable.
- Tracks human join/leave events:
  - Any human joining:
    - Cancels any pending “enable hibernate” timer.
    - Keeps `sv_hibernate_when_empty` disabled.
  - When the **last human disconnects**:
    - Starts a timer for `HIBERNATE_DELAY_SEC` seconds.
    - After the delay:
      - If the server is **still empty** → sets `sv_hibernate_when_empty 1`.
      - If someone joined during the delay → keeps hibernate off.

This gives you a nice window where:

- `bm_emptyflag` can update the flag.
- Cron can safely check and restart.
- Only after that does the engine go into hibernate.

**Tunable constant:**

At the top of the file:

```c
#define HIBERNATE_DELAY_SEC 20.0
```

Change this value if you want a longer/shorter delay before hibernate is re-enabled.

**Install:**

Same as the other plugin:

1. Put `bm_hibernate_delay.sp` into:
   ```text
   addons/sourcemod/scripting/
   ```
2. Compile it:
   ```bash
   ./compile.sh bm_hibernate_delay.sp
   ```
3. Copy `bm_hibernate_delay.smx` into:
   ```text
   addons/sourcemod/plugins/
   ```
4. Change map or restart the server.

---

## 2. Installing the shell scripts

You can keep them in your home directory or in a dedicated `scripts/` folder.  
Examples below assume:

- `/home/USERNAME/empty_restart.sh`
- `/home/USERNAME/rotate_defaultmap.sh`

### 2.1 `empty_restart.sh`

**What it does:**

- Checks flag file:
  ```bash
  FLAG="/home/USERNAME/serverfiles/insurgency/addons/sourcemod/data/bm_server_empty.txt"
  if [ -f "$FLAG" ] && grep -qx "1" "$FLAG"; then
      /home/USERNAME/insserver restart
  fi
  ```
- So it **only restarts** the server if:
  - The flag file exists, **and**
  - The file has exactly one line with `1`.

**Install:**

1. Copy `empty_restart.sh` to your LGSM user’s home:
   ```bash
   cp empty_restart.sh /home/USERNAME/empty_restart.sh
   ```
2. Set strict permissions so only the owner can read/write/execute it:
   ```bash
   chmod 700 /home/USERNAME/empty_restart.sh
   ```
3. Edit it and make sure the `FLAG` path and `insserver` path match your setup.

---

### 2.2 `rotate_defaultmap.sh`

**What it does:**

- Reads your coop mapcycle:
  ```bash
  MAPCYCLE="/home/USERNAME/serverfiles/insurgency/coop_custom.txt"
  ```
- For each line, it:
  - Trims whitespace.
  - Skips empty lines.
  - Skips lines where the first non-space character is `//`, `#` or `;`.
  - Strips inline `//` comments at the end of a line.
- Remaining lines should look like:
  ```text
  ministry_coop checkpoint
  ins_desert_atrocity_a1 checkpoint
  ```
- Picks a **random line** and writes that into LGSM’s `insserver.cfg`:

  ```bash
  CFG="/home/USERNAME/lgsm/config-lgsm/insserver/insserver.cfg"
  ...
  awk -v new="defaultmap=\"$CHOICE\"" '...'
  ```

So next time you run `./insserver start` or `./insserver restart`,  
the server starts on that **random map + gamemode**.

**Install:**

1. Copy the script:
   ```bash
   cp rotate_defaultmap.sh /home/USERNAME/rotate_defaultmap.sh
   ```
2. Set strict permissions so only the owner can read/write/execute it:
   ```bash
   chmod 700 /home/USERNAME/rotate_defaultmap.sh
   ```
3. Edit the variables at the top:
   - `CFG` → path to your LGSM `insserver.cfg`.
   - `MAPCYCLE` → path to your `coop_custom.txt`.
4. Test it manually:
   ```bash
   /home/USERNAME/rotate_defaultmap.sh
   grep '^defaultmap=' /home/USERNAME/lgsm/config-lgsm/insserver/insserver.cfg
   ```
   You should see a new random `defaultmap="..."` line.

---

## 3. Map list – `coop_custom.txt` (example)

Your map list file might look like this:

```text
ins_bridgeatremagen_coop checkpoint
karkand_redux_p2 checkpoint
ins_mountain_escape_v1_3 checkpoint
sotu_city checkpoint
glycencity checkpoint
...
// flakturm checkpoint // crashing clients on join
sotu_keep_v1 checkpoint
...
```

Rules:

- One map per line: `mapname checkpoint`
- You can comment out maps with:
  - `// this map is disabled`
  - `# this is a comment`
  - `; also a comment`
- `rotate_defaultmap.sh` **ignores** commented/empty lines automatically.

---

## 4. Setting up cron

Open `cron jobs.txt` – it contains an example `crontab`:

```text
*/5 * * * * /home/USERNAME/insserver monitor > /dev/null 2>&1
0 4 * * * /home/USERNAME/empty_restart.sh >/dev/null 2>&1
0 3 * * * /home/USERNAME/rotate_defaultmap.sh >/dev/null 2>&1
```

**Meaning:**

- `*/5 * * * *` – every 5 minutes:
  - `insserver monitor` → LGSM auto-starts the server if it crashed / is down.
- `0 3 * * *` – every day at 03:00:
  - Run `rotate_defaultmap.sh` to choose a new default map for the next restart.
- `0 4 * * *` – every day at 04:00:
  - Run `empty_restart.sh` – if the server is empty (`bm_server_empty.txt` = `1`), restart the server (which will now start on the random map chosen earlier).

> ⏱️ You can swap times or add more runs if you like (e.g. every 6 hours instead of once per day).

**Installing the cron jobs:**

1. Log in as your LGSM user (e.g. `su - USERNAME`).
2. Edit that user’s crontab:
   ```bash
   crontab -e
   ```
3. Paste the contents of `cron jobs.txt`, after:
   - Replacing `USERNAME` with your actual username.
   - Adjusting paths if you moved the scripts (e.g. `/home/USERNAME/scripts/...`).
4. Save and exit. Cron will pick up the changes automatically.

---

## 5. Quick setup checklist

1. ✅ SourceMod installed on Insurgency server.
2. ✅ Compile and install:
   - `bm_emptyflag.sp` → `bm_emptyflag.smx`
   - `bm_hibernate_delay.sp` → `bm_hibernate_delay.smx`
3. ✅ Ensure `sv_hibernate_when_empty` is enabled in your server config (the plugin controls when it actually kicks in).
4. ✅ Place and secure permissions:
   - `/home/USERNAME/empty_restart.sh` (`chmod 700`)
   - `/home/USERNAME/rotate_defaultmap.sh` (`chmod 700`)
5. ✅ Create / maintain `coop_custom.txt` with the maps you want.
6. ✅ Add cron entries from `cron jobs.txt` (edited for your paths and username).
7. ✅ Watch your server:
   - It should restart only when empty.
   - Startup map should change according to your coop map list.
