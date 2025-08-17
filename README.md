# Multichain Docker Deployment

This repository provides a simple way to deploy a [Multichain](https://www.multichain.com/) node using Docker.

## Project Structure

- `Dockerfile` — Builds the Multichain node image (version 2.3.3)
- `deploy-multichain.sh` — Script to build and run the Multichain node in Docker
- `.env.example` — Example environment variables for connecting to Multichain (e.g., from Laravel)

## Quick Start

1. **Clone this repository**

   ```sh
   git clone https://github.com/leodyversemilla07/multichain-docker.git
   cd multichain-docker
   ```

2. **Make the deploy script executable:**

   ```sh
   chmod +x deploy-multichain.sh
   ```


3. **Deploy the Multichain node:**

    ```sh
    ./deploy-multichain.sh [hostname] <chain-name> [container-name] [data-volume] [p2p-port] [rpc-port] <rpcuser> <rpcpassword> [rpcallowip] [connect_peer]
    ```

    - Example (first node):
       ```sh
       ./deploy-multichain.sh myhost mychain mychain_container mychain_data 8000 8001 user pass 0.0.0.0/0
       ```
    - Example (join as peer):
       ```sh
       ./deploy-multichain.sh myhost2 mychain mychain_container2 mychain_data2 8002 9002 user pass 0.0.0.0/0 172.17.0.2:8000
       ```
       (Replace `172.17.0.2:8000` with the P2P address from the first node's logs)
    - Use `-` for hostname if you want to skip setting it.
    - **Defaults:**
       - `chain-name`: `yourchain`
       - `container-name`: `multichain`
       - `data-volume`: `multichain_data`
       - `p2p-port`: `8000`
       - `rpc-port`: `8001`
       - `rpcuser`: `rpcuser`
       - `rpcpassword`: `rpcpassword`
       - `rpcallowip`: `0.0.0.0/0`
    - The optional `rpcallowip` argument lets you control which IPs can access the RPC interface (for security, restrict this in production).
    - The optional `connect_peer` argument lets you join this node to an existing peer (multi-node setup).

4. **Environment Variables**
   - See `.env.example` for sample connection settings (useful for Laravel or other apps):
     ```env
     MULTICHAIN_HOSTNAME=multichain
     MULTICHAIN_HOST=128.199.67.162
     MULTICHAIN_CHAIN_NAME=yourchain
     MULTICHAIN_P2P_PORT=8000
     MULTICHAIN_RPC_PORT=8001
     MULTICHAIN_RPC_USER=rpcuser
     MULTICHAIN_RPC_PASSWORD=rpcpassword
     ```
   - `MULTICHAIN_HOSTNAME` is the internal Docker hostname (for use within Docker networks).
   - `MULTICHAIN_HOST` is the external/public IP or DNS name for connecting from outside Docker (e.g., from your app server or the internet).

## Docker Details

- The Docker image is built from Ubuntu 22.04 and installs Multichain 2.3.3.
- Data is persisted in a Docker volume (default: `multichain_data`, configurable via the deploy script).
- Ports `8000` (P2P) and `8001` (RPC) are exposed by default, but you can customize them.

## Example Docker Commands

**Build the image manually:**

```sh
docker build -t my-multichain:2.3.3 .
```

**Run the container manually:**

```sh
docker run -d \
   --name mychain_container \
   -v mychain_data:/root/.multichain \
   -p 8000:8000 -p 8001:8001 \
   my-multichain:2.3.3 \
   yourchain -rpcuser=rpcuser -rpcpassword=rpcpassword -daemon
```

## Multi-Server Deployment: Connecting Nodes Across Servers

To deploy one Multichain node on Server A and another on Server B, and connect them as peers:

### 1. Prepare Both Servers

- Install Docker and copy this `multichain-docker` project to both servers.

### 2. Deploy the First Node (Server A)

- On Server A, run the deploy script to create the chain and start the first node:
   ```sh
   ./deploy-multichain.sh nodeA mychain mychain_containerA mychain_dataA 8000 9001 userA passA 0.0.0.0/0
   ```
- Note the public IP of Server A and the P2P port (e.g., 8000).

### 3. Get the Connect String for Peers

- On Server A, get the connect string for other nodes:
   ```sh
   docker logs mychain_containerA
   ```
- Look for a line like:
   ```
   multichaind mychain@<ServerA_IP>:<P2P_PORT>
   ```

### 4. Deploy the Second Node (Server B) and Connect to Server A

- On Server B, run the deploy script, passing the connect string from Server A as the last argument:
   ```sh
   ./deploy-multichain.sh nodeB mychain mychain_containerB mychain_dataB 8000 9002 userB passB 0.0.0.0/0 <ServerA_IP>:8000
   ```
- This will start node B and connect it to node A as a peer.

### 5. Open Firewall Ports

- Ensure both servers allow inbound traffic on their P2P and RPC ports (e.g., 8000, 9001, 9002).

### 6. Validate Peer Connection

- On both servers, use the `getpeerinfo` RPC call to confirm they see each other as peers:
   ```sh
   curl --user <rpcuser>:<rpcpassword> --data-binary '{"method":"getpeerinfo","params":[],"id":1}' -H 'content-type:text/plain;' http://127.0.0.1:<rpcport>
   ```

**Notes:**
- Both servers must be able to reach each other’s P2P port (default 8000).
- Use the connect string from the first node’s logs when starting the second node.
- Credentials and chain name must match on both nodes.



---

## Security Notes

- Use the `rpcallowip` argument in the deploy script to restrict which IPs can access the RPC port. For production, only allow trusted sources.
- The `.env.example` now includes both internal (`MULTICHAIN_HOSTNAME`) and external (`MULTICHAIN_HOST`) host variables for clarity in different deployment scenarios.

For more information, see the official [Multichain documentation](https://www.multichain.com/developers/).
