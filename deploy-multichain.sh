#!/bin/bash
# Deploy Multichain node in Docker

# Usage: ./deploy-multichain.sh [hostname] <chain-name> [container-name] [data-volume] [p2p-port] [rpc-port] <rpcuser> <rpcpassword> [rpcallowip] [connect_peer]

HOSTNAME=$1
CHAIN_NAME=${2:-yourchain}
CONTAINER_NAME=${3:-multichain}
DATA_VOLUME=${4:-multichain_data}
P2P_PORT=${5:-8000}
RPC_PORT=${6:-8001}
RPCUSER=${7:-rpcuser}
RPCPASSWORD=${8:-rpcpassword}

RPCALLOWIP=${9:-0.0.0.0/0}
CONNECT_PEER=${10}

# Build the Docker image (if not already built)
sudo docker build -t my-multichain:2.3.3 .

# Remove any existing container with the specified name (stopped or running
if docker ps -a --format '{{.Names}}' | grep -Eq "^$CONTAINER_NAME$"; then
  echo "Removing existing '$CONTAINER_NAME' container..."
  sudo docker rm -f "$CONTAINER_NAME"
fi

# Always initialize the blockchain (safe to run even if already initialized)

echo "Initializing blockchain $CHAIN_NAME..."
docker run --rm -v "$DATA_VOLUME":/root/.multichain my-multichain:2.3.3 multichain-util create $CHAIN_NAME


# Guarantee multichain.conf is written before the first node start

sudo docker run --rm -v "$DATA_VOLUME":/root/.multichain busybox sh -c "mkdir -p /root/.multichain/$CHAIN_NAME && echo -e 'rpcuser=$RPCUSER\nrpcpassword=$RPCPASSWORD\nrpcallowip=$RPCALLOWIP' > /root/.multichain/$CHAIN_NAME/multichain.conf"

# Set the default-rpc-port in params.dat to match the user-supplied RPC_PORT

echo "Setting default-rpc-port in params.dat to $RPC_PORT..."
sudo docker run --rm -v "$DATA_VOLUME":/root/.multichain busybox sh -c "if [ -f /root/.multichain/$CHAIN_NAME/params.dat ]; then sed -i 's/^default-rpc-port = .*/default-rpc-port = $RPC_PORT/' /root/.multichain/$CHAIN_NAME/params.dat; fi"


# Run the Multichain node (no -daemon, so it stays in foreground)
if [ -n "$HOSTNAME" ] && [ "$HOSTNAME" != "-" ]; then
  if [ -n "$CONNECT_PEER" ]; then
    sudo docker run -d \
      --name "$CONTAINER_NAME" \
      --hostname "$HOSTNAME" \
      -v "$DATA_VOLUME":/root/.multichain \
      -p $P2P_PORT:8000 -p $RPC_PORT:$RPC_PORT \
      my-multichain:2.3.3 \
      multichaind $CHAIN_NAME@$CONNECT_PEER -rpcuser=$RPCUSER -rpcpassword=$RPCPASSWORD
  else
    sudo docker run -d \
      --name "$CONTAINER_NAME" \
      --hostname "$HOSTNAME" \
      -v "$DATA_VOLUME":/root/.multichain \
      -p $P2P_PORT:8000 -p $RPC_PORT:$RPC_PORT \
      my-multichain:2.3.3 \
      multichaind $CHAIN_NAME -rpcuser=$RPCUSER -rpcpassword=$RPCPASSWORD
  fi
else
  if [ -n "$CONNECT_PEER" ]; then
    sudo docker run -d \
      --name "$CONTAINER_NAME" \
      -v "$DATA_VOLUME":/root/.multichain \
      -p $P2P_PORT:8000 -p $RPC_PORT:$RPC_PORT \
      my-multichain:2.3.3 \
      multichaind $CHAIN_NAME@$CONNECT_PEER -rpcuser=$RPCUSER -rpcpassword=$RPCPASSWORD
  else
    sudo docker run -d \
      --name "$CONTAINER_NAME" \
      -v "$DATA_VOLUME":/root/.multichain \
      -p $P2P_PORT:8000 -p $RPC_PORT:$RPC_PORT \
      my-multichain:2.3.3 \
      multichaind $CHAIN_NAME -rpcuser=$RPCUSER -rpcpassword=$RPCPASSWORD
  fi
fi

echo "Multichain node deployed."
echo "Chain: $CHAIN_NAME"
echo "RPC user: $RPCUSER"
echo "RPC password: $RPCPASSWORD"
echo "RPC allow IP: $RPCALLOWIP"
echo "Data volume: $DATA_VOLUME (persistent)"
echo "Ports: $P2P_PORT (P2P), $RPC_PORT (RPC)"
