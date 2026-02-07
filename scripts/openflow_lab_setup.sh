#!/usr/bin/env bash
set -euo pipefail

BR="br-nopaxos"
NS_LIST=(client seq r0 r1 r2)

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "run as root: sudo $0" >&2
  exit 1
fi

need_cmd ip
need_cmd ovs-vsctl
need_cmd ovs-ofctl

if command -v systemctl >/dev/null 2>&1; then
  systemctl is-active --quiet openvswitch-switch || systemctl start openvswitch-switch
fi

# Clean stale topology from previous runs.
ovs-vsctl --if-exists del-br "$BR"
for ns in "${NS_LIST[@]}"; do
  ip netns del "$ns" 2>/dev/null || true
done

ovs-vsctl add-br "$BR"
ovs-vsctl set bridge "$BR" protocols=OpenFlow13
ip link set "$BR" up

# Create namespaces + veths.
create_ns() {
  local ns="$1"
  local ip4="$2"

  ip netns add "$ns"
  ip link add "veth-${ns}" type veth peer name eth0 netns "$ns"
  ip link set "veth-${ns}" up
  ovs-vsctl --may-exist add-port "$BR" "veth-${ns}"

  ip netns exec "$ns" ip link set lo up
  ip netns exec "$ns" ip link set eth0 up
  ip netns exec "$ns" ip addr add "${ip4}/24" dev eth0
}

create_ns client 10.10.0.20
create_ns seq    10.10.0.10
create_ns r0     10.10.0.11
create_ns r1     10.10.0.12
create_ns r2     10.10.0.13

get_ofport() {
  local ifname="$1"
  local p
  for _ in $(seq 1 20); do
    p="$(ovs-vsctl get Interface "$ifname" ofport 2>/dev/null | tr -d '[:space:]')"
    if [[ "$p" =~ ^[0-9]+$ ]] && [[ "$p" -gt 0 ]]; then
      echo "$p"
      return 0
    fi
    sleep 0.1
  done
  echo "failed to read OpenFlow port for $ifname" >&2
  exit 1
}

CLIENT_PORT="$(get_ofport veth-client)"
SEQ_PORT="$(get_ofport veth-seq)"
R0_PORT="$(get_ofport veth-r0)"
R1_PORT="$(get_ofport veth-r1)"
R2_PORT="$(get_ofport veth-r2)"

# OpenFlow policy:
# 1) client OUM packets (udp dst 10.10.0.255:12348) go to sequencer first
# 2) sequencer OUM packets are replicated to all replicas
# 3) everything else uses normal switching (ARP + unicast replies)
ovs-ofctl -O OpenFlow13 del-flows "$BR"
ovs-ofctl -O OpenFlow13 add-flow "$BR" "priority=300,in_port=${CLIENT_PORT},udp,nw_dst=10.10.0.255,tp_dst=12348,actions=output:${SEQ_PORT}"
ovs-ofctl -O OpenFlow13 add-flow "$BR" "priority=250,in_port=${SEQ_PORT},udp,nw_dst=10.10.0.255,tp_dst=12348,actions=output:${R0_PORT},output:${R1_PORT},output:${R2_PORT}"
ovs-ofctl -O OpenFlow13 add-flow "$BR" "priority=0,actions=normal"

echo "OpenFlow lab is ready."
echo "Bridge: $BR"
echo "Namespaces: ${NS_LIST[*]}"
echo
echo "Interface/IP mapping:"
echo "  client: 10.10.0.20 (eth0 in ns client)"
echo "  sequencer: 10.10.0.10 (eth0 in ns seq)"
echo "  replica0: 10.10.0.11 (eth0 in ns r0)"
echo "  replica1: 10.10.0.12 (eth0 in ns r1)"
echo "  replica2: 10.10.0.13 (eth0 in ns r2)"
echo
echo "OpenFlow rules:"
ovs-ofctl -O OpenFlow13 dump-flows "$BR"
