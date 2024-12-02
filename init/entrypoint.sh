#!/usr/bin/env sh
set -eu

# Check if DB is already initialized
if [ -f "/var/lib/merlin/db_initialized.txt" ]; then
  echo "Db initialized already"
  exit 0
fi

git clone https://github.com/0xPolygon/cdk-validium-node.git
cd cdk-validium-node
go build -o ./build ./cmd
cp /tmp/snapshot_restore.toml snapshot_restore.toml

# set environment in /tmp/snapshot_restore.toml and prefix
if [ "$NETWORK" = "mainnet" ]; then
    snapshot_prefix=""
    sed -i 's/TO_REPLACE_HERE/production/' ./snapshot_restore.toml
else
    snapshot_prefix="testnet_"
    sed -i 's/TO_REPLACE_HERE/development/' ./snapshot_restore.toml
fi

wget -c -O state_db.sql.tar.gz  https://rpc-snapshot.merlinchain.io/${snapshot_prefix}state_db.sql.tar.gz --progress=dot
wget -c -O prover_db.sql.tar.gz https://rpc-snapshot.merlinchain.io/${snapshot_prefix}prover_db.sql.tar.gz --progress=dot

./build restore --cfg ./snapshot_restore.toml -is ./state_db.sql.tar.gz -ih ./prover_db.sql.tar.gz

# Execute script.sql for extra index for state db
PGPASSWORD="state_password" psql -h cdk-validium-state-db -U state_user -d state_db -f /tmp/script.sql

# Mark DB as initialized
echo "done" > /var/lib/merlin/db_initialized.txt
