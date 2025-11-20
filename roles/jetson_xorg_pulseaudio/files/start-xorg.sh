#!/bin/bash
# start-xorg.sh — Rootless Xorg + PulseAudio bootstrap for Jetson kiosks
# Default: rotate every connected output to portrait safely (no double-rotation).
# Optional overrides via /etc/eco/portrait.conf.
set -euo pipefail

USER_NAME="$(id -un)"
MYUID="$(id -u)"
export DISPLAY=":0"

echo "[INFO] Starting Xorg for user: ${USER_NAME} (UID: ${MYUID})"

# ------------------------------------------------------------------------------
# Robust XDG runtime handling: prefer logind dir only if owned by me & writable
# ------------------------------------------------------------------------------
RUNDIR_SYS="/run/user/${MYUID}"
RUNDIR_FALLBACK="/tmp/eco-runtime-${MYUID}"

owner="$(stat -c %u "${RUNDIR_SYS}" 2>/dev/null || echo -1)"
if [[ -d "${RUNDIR_SYS}" && -w "${RUNDIR_SYS}" && "${owner}" -eq "${MYUID}" ]]; then
  export XDG_RUNTIME_DIR="${RUNDIR_SYS}"
else
  echo "[WARN] /run/user/${MYUID} not usable (owner=${owner}); using ${RUNDIR_FALLBACK}"
  mkdir -p "${RUNDIR_FALLBACK}"
  chmod 700 "${RUNDIR_FALLBACK}" || true
  export XDG_RUNTIME_DIR="${RUNDIR_FALLBACK}"
fi

# Prefer runtime .Xauthority, but fall back to $HOME if we cannot write there
XAUTH_CANDIDATE="${XDG_RUNTIME_DIR}/.Xauthority"
if ( : >"${XAUTH_CANDIDATE}" ) 2>/dev/null; then
  export XAUTHORITY="${XAUTH_CANDIDATE}"
else
  echo "[WARN] Cannot write ${XAUTH_CANDIDATE}; using \$HOME/.Xauthority"
  export XAUTHORITY="$HOME/.Xauthority"
  : >"${XAUTHORITY}" 2>/dev/null || true
fi
chmod 600 "${XAUTHORITY}" 2>/dev/null || true
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"


# ------------------------------------------------------------------------------
# Optional overrides (all keys optional):
#   OUTPUT=DP-1
#   EDID_MATCH="(LG|DELL)"
#   FORCE_ROTATE=right|left|normal|inverted
#   PRIMARY=true|false           (default true)
#   LAYOUT=single|mirror|extend-right|extend-left  (default single)
#   DISABLE_DPMS=true|false      (default true)
# ------------------------------------------------------------------------------
CFG="/etc/eco/portrait.conf"
if [[ -f "$CFG" ]]; then
  echo "[INFO] Loading $CFG"
  # shellcheck disable=SC1090
  source "$CFG"
fi
PRIMARY="${PRIMARY:-true}"
LAYOUT="${LAYOUT:-single}"
DISABLE_DPMS="${DISABLE_DPMS:-true}"

# ------------------------------------------------------------------------------
# Cleanup: kill leftover Xorg, clear X locks with tiny audited helper if present
# ------------------------------------------------------------------------------
pkill -x Xorg || true
if command -v sudo >/dev/null 2>&1 && [[ -x /usr/local/sbin/eco-x-clean ]]; then
  sudo /usr/local/sbin/eco-x-clean || true
fi

# Fresh Xauthority (don’t assume existing file works)
rm -f "${XAUTHORITY}" 2>/dev/null || true
touch "${XAUTHORITY}"
chmod 600 "${XAUTHORITY}"
xauth generate :0 . trusted >/dev/null 2>&1 || true
xauth add :0 . "$(mcookie)"   >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# Launch Xorg (rootless, no TCP)
# ------------------------------------------------------------------------------
echo "[INFO] Launching Xorg..."
Xorg "${DISPLAY}" vt7 -nolisten tcp &

# Wait for X socket to appear
for i in {1..40}; do
  if [[ -S /tmp/.X11-unix/X0 ]] && pgrep -x Xorg >/dev/null 2>&1; then
    echo "[SUCCESS] Xorg is running"
    break
  fi
  echo "[WAIT] Waiting for Xorg... ($i/40)"
  sleep 0.5
done

# ------------------------------------------------------------------------------
# PulseAudio (user). Remove stale native socket if nobody is listening.
# ------------------------------------------------------------------------------
if [[ -S "${XDG_RUNTIME_DIR}/pulse/native" ]]; then
  if ! (command -v lsof >/dev/null 2>&1 && lsof -U "${XDG_RUNTIME_DIR}/pulse/native" >/dev/null 2>&1); then
    rm -f "${XDG_RUNTIME_DIR}/pulse/native" || true
  fi
fi
pulseaudio --check >/dev/null 2>&1 || pulseaudio --start >/dev/null 2>&1 || true

# Allow local clients (containers) to access X
xhost +SI:localuser:${USER_NAME} >/dev/null 2>&1 || true
xhost +SI:localuser:root       >/dev/null 2>&1 || true

# ------------------------------------------------------------------------------
# RANDR helpers
# ------------------------------------------------------------------------------
echo "[INFO] Probing outputs..."
for i in {1..12}; do
  if xrandr >/dev/null 2>&1; then break; fi
  echo "[WAIT] xrandr not ready... ($i/12)"
  sleep 0.5
done

# Connected outputs
mapfile -t ALL_OUTS < <(xrandr | awk '/ connected/{print $1}')
if [[ "${#ALL_OUTS[@]}" -eq 0 ]]; then
  echo "[WARN] No connected outputs detected; leaving X running."
  echo "[SUCCESS] Xorg & PulseAudio ready"
  exit 0
fi

# Choose a primary output (for --primary and single layout)
choose_primary_output() {
  local out=""
  if [[ -n "${OUTPUT:-}" ]]; then
    if xrandr | awk -v o="$OUTPUT" '$1==o && / connected/{ok=1} END{exit ok?0:1}'; then
      echo "$OUTPUT"; return 0
    else
      echo "[WARN] OUTPUT=$OUTPUT not connected; auto-selecting." >&2
    fi
  fi
  if [[ -n "${EDID_MATCH:-}" ]]; then
    out="$(xrandr --verbose | awk -v RS= -v IGNORECASE=1 -v re="$EDID_MATCH" '
           / connected/ && $0 ~ re {print $1; exit}')"
    [[ -n "$out" ]] && { echo "$out"; return 0; }
    echo "[WARN] No EDID match for /$EDID_MATCH/; auto-selecting." >&2
  fi
  xrandr | awk '/ connected/{print $1; exit}'
}
PRIMARY_OUT="$(choose_primary_output)"

# Decide rotation per output; avoid double-rotation
rotation_for_output() {
  local out="$1"
  local forced="${FORCE_ROTATE:-}"
  if [[ -n "$forced" ]]; then
    echo "$forced"; return
  fi
  # Preferred (star) or first mode
  local line mode
  line="$(xrandr --query | awk -v o="$out" '
           $1==o && $2=="connected"{f=1; next}
           f && $2 ~ /\*/ {print; exit}
           f && $1=="" {exit}')"
  mode="$(awk '{print $1}' <<<"$line")"
  [[ -z "$mode" ]] && mode="$(xrandr --query | awk -v o="$out" '
                               $1==o && $2=="connected"{f=1; next}
                               f && $1 ~ /^[0-9]+x[0-9]+/ {print $1; exit}')"
  [[ -z "$mode" ]] && mode="1920x1080"

  mode="${mode%%_*}"            # strip refresh suffix like _60.00
  local w="${mode%x*}"
  local h="${mode#*x}"
  if (( h > w )); then
    echo "normal"               # already portrait: do not rotate
  else
    echo "right"                # landscape -> rotate to portrait
  fi
}

# Apply per-output rotation and mode
for OUT in "${ALL_OUTS[@]}"; do
  ROT="$(rotation_for_output "$OUT")"
  MODE="$(xrandr --query | awk -v o="$OUT" '
           $1==o && $2=="connected"{f=1; next}
           f && $2 ~ /\*/ {print $1; exit}
           f && $1=="" {exit}')"
  [[ -z "$MODE" ]] && MODE="preferred"

  echo "[INFO] ${OUT}: mode=${MODE} rotate=${ROT}"
  if [[ "$MODE" == "preferred" ]]; then
    xrandr --output "$OUT" --auto  --rotate "$ROT" || true
  else
    xrandr --output "$OUT" --mode "$MODE" --rotate "$ROT" || true
  fi

  # Optional: reduce tearing if tool available
  if command -v nvidia-settings >/dev/null 2>&1; then
    nvidia-settings --assign "CurrentMetaMode=${OUT}: nvidia-auto-select { ForceFullCompositionPipeline=On }" \
      >/dev/null 2>&1 || true
  fi
done

# Layout policy
case "${LAYOUT}" in
  single)
    for d in "${ALL_OUTS[@]}"; do
      [[ "$d" != "$PRIMARY_OUT" ]] && xrandr --output "$d" --off || true
    done
    ;;
  mirror)
    : # already set each output; mirroring native sizes is fine for kiosk
    ;;
  extend-right|extend-left)
    offset=0; sign=1; [[ "$LAYOUT" == "extend-left" ]] && sign=-1
    for d in "${ALL_OUTS[@]}"; do
      xrandr --output "$d" --pos "$offset"x0 || true
      w="$(xrandr | awk -v o="$d" '
            $1==o && $2=="connected"{f=1; next}
            f && $2 ~ /\*/ {split($1,a,"x"); print a[1]; exit}')"
      : "${w:=1080}"
      offset=$((offset + sign*w))
    done
    ;;
esac

[[ "${PRIMARY}" == "true" ]] && xrandr --output "$PRIMARY_OUT" --primary || true

# DPMS / blanking (no-op if server disallows)
if [[ "${DISABLE_DPMS}" == "true" ]]; then
  xset -dpms     >/dev/null 2>&1 || true
  xset s off     >/dev/null 2>&1 || true
  xset s noblank >/dev/null 2>&1 || true
fi

echo "[INFO] Current xrandr:"
xrandr || true
echo "[SUCCESS] Xorg & PulseAudio ready (portrait-by-default applied)"
