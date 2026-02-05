# Docker Deployment Guide for NOPaxos

## Overview

This repository includes multiple replication protocols that can be deployed in Docker containers. **VR (Viewstamped Replication) mode works out of the box**, while NOPaxos mode requires additional network configuration.

## Quick Start - VR Mode (Recommended for Testing)

VR (Viewstamped Replication) mode works immediately without requiring a sequencer:

```bash
# Use the VR configuration
docker-compose up -d

# View logs
docker-compose logs -f

# Stop containers
docker-compose down
```

The current `docker-compose.yml` is configured for VR mode. You should see successful request completion with latency metrics.

## Available Replication Modes

The repository supports 5 different replication protocols:

1. **`vr`** - Viewstamped Replication (Multi-Paxos) **Works in Docker**
2. **`nopaxos`** - Network Ordered Paxos **Requires network setup**
3. **`spec`** - Speculative Paxos **Works in Docker**
4. **`fastpaxos`** - Fast Paxos **Works in Docker**
5. **`unreplicated`** - No replication **Works in Docker**

## Network Architecture

### Current Setup (Bridge Network)

- **Network**: `192.168.100.0/24` (Docker bridge)
- **Sequencer**: `192.168.100.10` (only for NOPaxos mode)
- **Replica 0**: `192.168.100.11:12345`
- **Replica 1**: `192.168.100.12:12345`
- **Replica 2**: `192.168.100.13:12345`
- **Client**: `192.168.100.20`
- **Multicast**: `224.0.0.1:12348`

## Switching Between Modes

### Option 1: Edit docker-compose.yml

Change the `-m` flag in the command for replicas and client:

```yaml
# For VR mode
command: /bin/bash -c "sleep 5 && ./bench/replica -c nopaxos-replica.conf -i 0 -m vr"

# For Speculative Paxos
command: /bin/bash -c "sleep 5 && ./bench/replica -c nopaxos-replica.conf -i 0 -m spec"

# For Fast Paxos
command: /bin/bash -c "sleep 5 && ./bench/replica -c nopaxos-replica.conf -i 0 -m fastpaxos"
```

### Option 2: Use docker-compose Profiles

See the specialized compose files:
- `docker-compose.yml` - VR mode (current)
- `docker-compose.nopaxos.yml` - NOPaxos with sequencer
- `docker-compose.spec.yml` - Speculative Paxos

## NOPaxos Mode - Special Requirements

NOPaxos mode requires the **sequencer to intercept packets in the network path**. This doesn't happen automatically in Docker.

### Why NOPaxos Doesn't Work Out of the Box

From the NOPaxos README:
> "In order to run NOPaxos, you need to configure the network to route OUM packets first to the sequencer, and then multicast to all OUM receivers. The easiest way is to use OpenFlow and install rules that match on the multicast address."

In standard Docker networking:
- Packets flow directly from client → replicas via the Docker bridge
- The sequencer never sees or intercepts these packets
- NOPaxos protocol cannot function

## Testing and Verification

### Check Container Status
```bash
docker-compose ps
```

### View Live Logs
```bash
# All containers
docker-compose logs -f

# Specific containers
docker-compose logs -f replica0 client
```

### Test Network Connectivity
```bash
# Ping from client to replica
docker exec nopaxos-client ping -c 3 192.168.100.11

# Check listening ports on replica
docker exec nopaxos-replica-0 ss -tuln | grep 12345
```

### Inspect Network
```bash
# View network configuration
docker network inspect nopaxos_nopaxos-net

# Check container IPs
docker inspect nopaxos-replica-0 | grep IPAddress
```

## Performance Testing

### Run Benchmark
The client runs 100 requests by default. To change this:

```yaml
client:
  command: /bin/bash -c "sleep 10 && ./bench/client -c nopaxos-replica.conf -m vr -n 1000"
  # -n 1000 = 1000 requests
```

### Interpret Results
Look for these metrics in client logs:
- **Median latency**: Typical request latency
- **90th/95th/99th percentile**: Tail latency
- **Throughput**: Requests per second

Example output:
```
Completed 100 requests in 0.009488 seconds
Median latency is 79019 ns (79 us)
90th percentile latency is 114152 ns (114 us)
```

## Troubleshooting

### Issue: "Gap request timed out" or "Client timeout"

**Cause**: Using NOPaxos mode without proper network configuration.

**Solution**: Switch to VR mode or set up OpenFlow.

### Issue: Containers can't communicate

```bash
# Test basic connectivity
docker exec nopaxos-client ping 192.168.100.11

# Check if replicas are listening
docker exec nopaxos-replica-0 ss -tuln | grep 12345

# Verify network exists
docker network ls | grep nopaxos
```

### Issue: Build failures

```bash
# Clean rebuild
docker-compose down
docker-compose build --no-cache
docker-compose up
```

### Issue: Sequencer not starting (NOPaxos mode)

The sequencer requires `privileged: true` for raw sockets. Check docker-compose.yml:

```yaml
sequencer:
  privileged: true
```

## Configuration Files

### nopaxos-replica.conf
```
f 1
replica 192.168.100.11:12345
replica 192.168.100.12:12345
replica 192.168.100.13:12345
multicast 224.0.0.1:12348
```

- `f 1`: Tolerate 1 failure (requires 3 replicas minimum)
- `replica`: IP:port for each replica
- `multicast`: Multicast group (used by NOPaxos)

### nopaxos-sequencer.conf (NOPaxos only)
```
interface eth0
groupaddr 224.0.0.1
```

- `interface`: Network interface in container
- `groupaddr`: Must match multicast address in replica config

## Advantages of Docker Deployment

**Fast startup** - Seconds vs minutes for VMs  
**Low resource usage** - MBs vs GBs of RAM  
**Easy management** - `docker-compose up/down`  
**Reproducible** - Same environment everywhere  
**Isolated** - Clean network separation  
**Portable** - Works on Linux, WSL2, macOS  

## Limitations

**NOPaxos requires network setup** - Use VR/Spec/Fast for simple Docker deployment  
**Performance not representative** - Docker adds overhead, use bare metal for benchmarks  
**WSL2 differences** - Some network features may behave differently than native Linux  

## Production Considerations

For production deployments:
1. Use bare metal or VMs, not containers
2. If using NOPaxos, deploy proper OpenFlow switches
3. Use dedicated network interfaces
4. Tune Linux network stack parameters
5. Monitor network latency and packet loss

## Reference

- [NOPaxos Paper (OSDI 2016)](http://homes.cs.washington.edu/~lijl/papers/nopaxos-osdi16.pdf)
- [Viewstamped Replication Revisited](http://pmg.csail.mit.edu/papers/vr-revisited.pdf)
- [Original README](README.md)



For questions or issues, refer to the [main README](README.md) or contact the NOPaxos team.

