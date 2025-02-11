#!/usr/bin/env bash
#
# pg_per_osd_ec_replicated.sh
#
# 1) Gets total OSD count from the cluster.
# 2) Lists each pool, checks if it's replicated or erasure-coded.
#    - For replicated pools, uses (pg_num * size) / OSD_COUNT.
#    - For EC pools, retrieves (k+m) from the pool's erasure-code profile,
#      then uses (pg_num * (k + m)) / OSD_COUNT.
# 3) Prints the "PG per OSD" for each pool.
#
# Requirements:
#   - ceph CLI
#   - jq

set -e

# ------------------------------------------------------------------------------
# 1) Get total number of OSDs
# ------------------------------------------------------------------------------
OSD_COUNT=$(ceph osd stat --format json | jq -r '.num_osds')
if [[ -z "$OSD_COUNT" || "$OSD_COUNT" -le 0 ]]; then
  echo "ERROR: Could not retrieve a valid OSD count!"
  exit 1
fi

# ------------------------------------------------------------------------------
# 2) Get pool details (type, size, pg_num, erasure_code_profile, etc.)
#    "ceph osd pool ls detail --format json" returns an array of pools.
# ------------------------------------------------------------------------------
POOL_DETAILS=$(ceph osd pool ls detail --format json)
if [[ -z "$POOL_DETAILS" ]]; then
  echo "ERROR: Could not retrieve pool details!"
  exit 1
fi

# We'll parse .type to see if it's replicated or ec.
# For Ceph versions:
#   type = 1 => replicated
#   type = 3 => erasure-coded
#
# (There might be older or alternate representations, but this is standard.)
#

# ------------------------------------------------------------------------------
# Function to retrieve and cache 'k' and 'm' for a given EC profile
# ------------------------------------------------------------------------------
declare -A EC_K
declare -A EC_M

get_ec_params() {
  local profile="$1"

  # If we've already cached this profile, skip the CLI call
  if [[ -n "${EC_K[$profile]}" && -n "${EC_M[$profile]}" ]]; then
    return
  fi

  # Retrieve the profile as JSON, e.g.:
  #   {
  #     "k": "2",
  #     "m": "1",
  #     ...
  #   }
  local profile_json
  profile_json=$(ceph osd erasure-code-profile get "$profile" --format json)

  # Extract k, m
  local k_val m_val
  # shellcheck disable=SC2086
  read -r k_val m_val < <(echo "$profile_json" | jq -r '[.k, .m] | @sh' | xargs echo)

  # Cache them
  EC_K["$profile"]="$k_val"
  EC_M["$profile"]="$m_val"
}

# ------------------------------------------------------------------------------
# 3) Loop over each pool and compute PG per OSD
# ------------------------------------------------------------------------------
echo "Total OSDs in cluster: $OSD_COUNT"
echo "=========================================================="

# We'll use jq to extract the needed fields and iterate:
echo "$POOL_DETAILS" | jq -r '
  .[] |
  {
    name: .pool_name,
    pg_num: .pg_num,
    type: .type,
    size: (if .type == 1 then .size else null end),
    ec_profile: (if .type == 3 then .erasure_code_profile else null end)
  } |
  "\(.name)\t\(.pg_num)\t\(.type)\t\(.size)\t\(.ec_profile)"
' | while IFS=$'\t' read -r POOL_NAME POOL_PG POOL_TYPE POOL_SIZE EC_PROFILE; do

  # POOL_TYPE=1 => replicated, POOL_TYPE=3 => EC
  if [[ "$POOL_TYPE" -eq 1 ]]; then
    # Replicated pool
    # Formula: PG per OSD = (pg_num * size) / OSD_COUNT
    if [[ -z "$POOL_SIZE" ]]; then
      echo "ERROR: Replicated pool '$POOL_NAME' has no 'size' field!"
      continue
    fi

    PG_PER_OSD=$(awk -v pg="$POOL_PG" -v sz="$POOL_SIZE" -v osd="$OSD_COUNT" '
      BEGIN {
        val = (pg * sz) / osd;
        printf "%.2f", val;
      }'
    )
    echo -e "Pool Name: \e[31m$POOL_NAME\e[0m"
    echo "  Type                : Replicated"
    echo "  Replication size    : $POOL_SIZE"
    echo "  Current PG count    : $POOL_PG"
#    echo "  PG per OSD (formula): ($POOL_PG * $POOL_SIZE) / $OSD_COUNT = $PG_PER_OSD"
    echo "  PG per OSD          : $PG_PER_OSD"
    echo

  elif [[ "$POOL_TYPE" -eq 3 ]]; then
    # Erasure-coded pool
    # 1) Retrieve the EC profile => get k, m
    if [[ -z "$EC_PROFILE" ]]; then
      echo "ERROR: EC pool '$POOL_NAME' has no 'erasure_code_profile'!"
      continue
    fi

    get_ec_params "$EC_PROFILE"
    K_VAL="${EC_K[$EC_PROFILE]}"
    M_VAL="${EC_M[$EC_PROFILE]}"
    if [[ -z "$K_VAL" || -z "$M_VAL" ]]; then
      echo "ERROR: Could not determine k and m for profile '$EC_PROFILE'!"
      continue
    fi

    # Formula: PG per OSD = (pg_num * (k + m)) / OSD_COUNT
    PG_PER_OSD=$(awk -v pg="$POOL_PG" -v k="$K_VAL" -v m="$M_VAL" -v osd="$OSD_COUNT" '
      BEGIN {
        val = (pg * (k + m)) / osd;
        printf "%.2f", val;
      }'
    )

    echo -e "Pool Name: \e[31m$POOL_NAME\e[0m"
    echo "  Type                : Erasure-coded"
#    echo "  EC profile          : $EC_PROFILE"
    echo "  k + m               : $K_VAL + $M_VAL"
    echo "  Current PG count    : $POOL_PG"
#    echo "  PG per OSD (formula): ($POOL_PG * ($K_VAL + $M_VAL)) / $OSD_COUNT = $PG_PER_OSD"
    echo "  PG per OSD          : $PG_PER_OSD"
    echo
  else
    echo "Pool Name: $POOL_NAME"
    echo "  Unrecognized type: $POOL_TYPE (not 1, not 3). Skipping."
    echo
  fi

done
