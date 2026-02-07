#!/usr/bin/env bash
set -euo pipefail

BR="br-nopaxos"
NS_LIST=(client seq r0 r1 r2)

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root: sudo $0" >&2
  exit 1
fi

for ns in "${NS_LIST[@]}"; do
  if ip netns list | awk '{print $1}' | grep -qx "$ns"; then
    pids="$(ip netns pids "$ns" || true)"
    if [[ -n "$pids" ]]; then
      kill $pids 2>/dev/null || true
      sleep 0.2
      kill -9 $pids 2>/dev/null || true
    fi
  fi
done

ovs-vsctl --if-exists del-br "$BR"

for ns in "${NS_LIST[@]}"; do
  ip netns del "$ns" 2>/dev/null || true
done

echo "OpenFlow lab cleaned."
