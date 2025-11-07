#!//bin/bash
# Nov 2025
# 45Drives
# Matthew Hutchinson <mhutchinson@45drives.com>

set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1"; exit 1; }; }
need ceph
need ceph-volume
need lvs
need readlink
need systemctl
need awk

stop_osd() { systemctl stop "ceph-osd@$1" 2>/dev/null || true; }
start_osd() { systemctl start "ceph-osd@$1" 2>/dev/null || true; }

to_vg_lv() {
  local dev="$1"
  if [[ "$dev" =~ ^/dev/[^/]+/[^/]+$ ]]; then
    awk -F'/' '{print $3"/"$4}' <<<"$dev"
    return 0
  fi
  local vg lv
  read -r vg lv < <(lvs --noheadings -o vg_name,lv_name "$dev" 2>/dev/null | awk '{print $1, $2}')
  if [[ -n "${vg:-}" && -n "${lv:-}" ]]; then
    printf "%s/%s\n" "$vg" "$lv"
    return 0
  fi
  return 1
}

mapfile -t DB_LINKS < <(ls /var/lib/ceph/osd/ceph-*/block.db 2>/dev/null | while read -r p; do [[ -L "$p" ]] && echo "$p"; done)

if [[ ${#DB_LINKS[@]} -eq 0 ]]; then
  echo "No OSDs on this host have a separate DB. Nothing to do."
  exit 0
fi

OSD_IDS=()
for link in "${DB_LINKS[@]}"; do
  osd_id="$(basename "$(dirname "$link")" | cut -d- -f2)"
  OSD_IDS+=("$osd_id")
done

echo "OSDs to migrate on this host:"
printf "%s\n" "${OSD_IDS[@]}"

echo
read -rp "Continue and migrate all of the above OSDs now? [y/N] " go
[[ "$go" =~ ^[Yy]$ ]] || { echo "Aborted"; exit 0; }

echo
echo "Setting noout for this host"
ceph osd set noout || true
cleanup() { echo; echo "Clearing noout"; ceph osd unset noout || true; }
trap cleanup EXIT

DB_LVS_TO_REMOVE=()

for osd_id in "${OSD_IDS[@]}"; do
  osd_dir="/var/lib/ceph/osd/ceph-$osd_id"
  [[ -d "$osd_dir" ]] || { echo "Skipping OSD $osd_id (no directory)"; continue; }

  fsid="$(cat "$osd_dir/fsid" 2>/dev/null || true)"
  block_link="$(readlink "$osd_dir/block" || true)"
  block_real="$(readlink -f "$osd_dir/block" || true)"
  db_lv_link="$(readlink "$osd_dir/block.db" || true)"

  if [[ -z "$fsid" || -z "$db_lv_link" ]]; then
    echo "Skipping OSD $osd_id (missing fsid or block.db)"
    continue
  fi

  target=""
  if target="$(to_vg_lv "$block_link")"; then :; elif target="$(to_vg_lv "$block_real")"; then :; else
    echo "Skipping OSD $osd_id (target vg/lv not found)"
    continue
  fi

  echo
  echo "Migrating OSD $osd_id to $target"

  stop_osd "$osd_id"
  ceph-volume lvm migrate --osd-id "$osd_id" --osd-fsid "$fsid" --from db wal --target "$target"
  start_osd "$osd_id"

  DB_LVS_TO_REMOVE+=("$db_lv_link")
done

echo
echo "All migrations complete."

if (( ${#DB_LVS_TO_REMOVE[@]} > 0 )); then
  echo
  read -rp "Do you want to remove the old DB LVs to reclaim space? [y/N] " rmdb
  if [[ "$rmdb" =~ ^[Yy]$ ]]; then
    for p in "${DB_LVS_TO_REMOVE[@]}"; do
      echo "Removing $p"
      lvremove -y "$p" || echo "lvremove failed for $p"
    done
  else
    echo
    echo "You chose to keep the old DB LVs. You can remove them later using:"
    for p in "${DB_LVS_TO_REMOVE[@]}"; do
      echo "  lvremove -y $p"
    done
  fi
fi

echo
echo "Done."
