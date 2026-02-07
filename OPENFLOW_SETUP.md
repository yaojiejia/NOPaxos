# NOPaxos OpenFlow Setup Guide (No Docker)

This guide runs NOPaxos locally with Open vSwitch + OpenFlow so Ordered Unreliable
Multicast (OUM) packets are routed:

1. client -> sequencer
2. sequencer -> replicas

This is the network behavior NOPaxos needs and is why plain local execution
without OpenFlow often times out.

## What this setup creates

The script `scripts/openflow_lab_setup.sh` builds this topology:

- OVS bridge: `br-nopaxos` (OpenFlow 1.3)
- Namespaces: `client`, `seq`, `r0`, `r1`, `r2`
- Per-namespace `eth0` links connected to the bridge
- IPs:
  - `client`: `10.10.0.20/24`
  - `seq`: `10.10.0.10/24`
  - `r0`: `10.10.0.11/24`
  - `r1`: `10.10.0.12/24`
  - `r2`: `10.10.0.13/24`
- OUM destination: `10.10.0.255:12348`

Matching config files are already provided:

- `nopaxos-replica.of.conf`
- `nopaxos-sequencer.of.conf`

## Prerequisites

### 1) System packages (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install -y \
  openvswitch-switch \
  protobuf-compiler pkg-config libunwind-dev libssl-dev \
  libprotobuf-dev libevent-dev libgtest-dev
```

### 2) Build binaries

From repo root:

```bash
make -j"$(nproc)"
```

Expected binaries:

- `./sequencer/sequencer`
- `./bench/replica`
- `./bench/client`

## Step 1: Create OpenFlow lab topology

```bash
sudo ./scripts/openflow_lab_setup.sh
```

Optional verification:

```bash
sudo ip netns list
sudo ovs-vsctl show
sudo ovs-ofctl -O OpenFlow13 dump-flows br-nopaxos
```

You should see three key flow entries:

- `priority=300` for `in_port=veth-client` and UDP dst `10.10.0.255:12348`
- `priority=250` for `in_port=veth-seq` and UDP dst `10.10.0.255:12348`
- `priority=0 actions=NORMAL`

## Step 2: Start NOPaxos processes

Run each in a separate terminal.

### Terminal 1: Sequencer

```bash
sudo ip netns exec seq ./sequencer/sequencer -c nopaxos-sequencer.of.conf
```

Note: sequencer usually prints little/no output while idle. That is expected.

### Terminal 2: Replica 0

```bash
sudo ip netns exec r0 ./bench/replica -c nopaxos-replica.of.conf -i 0 -m nopaxos
```

### Terminal 3: Replica 1

```bash
sudo ip netns exec r1 ./bench/replica -c nopaxos-replica.of.conf -i 1 -m nopaxos
```

### Terminal 4: Replica 2

```bash
sudo ip netns exec r2 ./bench/replica -c nopaxos-replica.of.conf -i 2 -m nopaxos
```

## Step 3: Run client

### Terminal 5

```bash
sudo ip netns exec client ./bench/client -c nopaxos-replica.of.conf -m nopaxos -n 1
```

Expected result:

- `Completed 1 requests ...`
- latency stats printed
- no repeating `Client timeout; resending request`

## Step 4: Verify OpenFlow path is used

After running the client:

```bash
sudo ovs-ofctl -O OpenFlow13 dump-flows br-nopaxos
```

Interpretation:

- `n_packets` on priority `300` should increase (client -> sequencer rule)
- `n_packets` on priority `250` should increase (sequencer -> replicas rule)
- This confirms OUM packets were intercepted and forwarded by OpenFlow.

## Running a larger benchmark

Example with 1000 requests:

```bash
sudo ip netns exec client ./bench/client -c nopaxos-replica.of.conf -m nopaxos -n 1000
```

## Changing fault tolerance (`f`)

If you change `f`, you must scale the lab topology too. Do not change only the
`f` line.

### Example: `f = 2`

Use `2f+1 = 5` replicas.

What to update:

- `nopaxos-replica.of.conf`
  - set `f 2`
  - define 5 `replica` entries (indices `0..4`)
- `scripts/openflow_lab_setup.sh`
  - add namespaces/interfaces/IPs for `r3` and `r4`
  - include `veth-r3` and `veth-r4` in the sequencer fanout OpenFlow rule
- `scripts/openflow_lab_cleanup.sh`
  - add `r3` and `r4` to namespace cleanup list
- process startup
  - run 5 replicas: `-i 0`, `-i 1`, `-i 2`, `-i 3`, `-i 4`

Protocol values in this codebase:

- quorum size = `f + 1`
- for `f = 2`, quorum is `3`

## Common issues and fixes

### `missing command: ovs-vsctl` or `ovs-ofctl`

Install OVS:

```bash
sudo apt-get install -y openvswitch-switch
```

### Client keeps timing out

Check:

```bash
sudo ovs-ofctl -O OpenFlow13 dump-flows br-nopaxos
```

If priority `300/250` packet counters are not moving:

- topology or flows are not active
- rerun setup script:

```bash
sudo ./scripts/openflow_lab_setup.sh
```

Also verify all processes are running:

```bash
sudo ip netns pids seq
sudo ip netns pids r0
sudo ip netns pids r1
sudo ip netns pids r2
```

### Replica bind errors (`Address already in use`)

Cleanup and restart:

```bash
sudo ./scripts/openflow_lab_cleanup.sh
sudo ./scripts/openflow_lab_setup.sh
```

Then relaunch sequencer/replicas/client.

## Teardown

When done:

```bash
sudo ./scripts/openflow_lab_cleanup.sh
```

This removes:

- bridge `br-nopaxos`
- namespaces `client`, `seq`, `r0`, `r1`, `r2`
