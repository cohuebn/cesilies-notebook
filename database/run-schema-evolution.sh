#!/usr/bin/env bash

split_on_commas() {
    local original_ifs=$IFS
    IFS=,
    local items=($1)
    for item in "${items[@]}"; do
        echo "$item"
    done
    IFS=$original_ifs
}
db_nodes=($(split_on_commas $1))
db_port=$2
certs_dir=$3
db_name=$4
service_user=$5
service_user_password=$6
changelog_path=$7

# Validate inputs
if [ ${#db_nodes[@]} -eq 0 ]; then
    echo "No database nodes provided; cannot run without any database nodes"
    exit 1
fi

# Create the root and service user's certs
[ ! -f "$certs_dir/client.root.crt" ] && cockroach cert create-client root --ca-key="$certs_dir/ca.local.key" --certs-dir=$certs_dir
[ ! -f "$certs_dir/client.$service_user.crt" ] && cockroach cert create-client $service_user --ca-key="$certs_dir/ca.local.key" --certs-dir=$certs_dir --also-generate-pkcs8-key

# Run a sql command to check if each node in the cluster has been initialized; if not initialize it
for db_node in $db_nodes; do
    echo "DB node: $db_node"
    cockroach sql --certs-dir="$certs_dir" --host "$db_node" --execute="select 1" \
        || cockroach init --certs-dir="$certs_dir" --host "$db_node"
done

# Ensure the database and schema migration user exist to allow further schema evolution
db_init_sql=$(cat <<EOF
CREATE DATABASE IF NOT EXISTS $db_name;
CREATE ROLE IF NOT EXISTS cesilies_notebook_deployer WITH CREATEDB;
GRANT ALL ON DATABASE $db_name TO cesilies_notebook_deployer;
CREATE USER IF NOT EXISTS $service_user WITH PASSWORD '$service_user_password';
GRANT cesilies_notebook_deployer TO $service_user;
EOF
)
first_db_node=${db_nodes[0]}
echo "Running migrations against db node: $first_db_node"
cockroach sql --certs-dir="$certs_dir" --host "$first_db_node" --execute "$db_init_sql"

db_url="jdbc:postgresql://$first_db_node:$db_port/$db_name?sslmode=verify-full&sslrootcert=$certs_dir/ca.crt&sslkey=$certs_dir/client.$service_user.key.pk8&sslcert=$certs_dir/client.$service_user.crt"
liquibase --changelog-file="$changelog_path" --url="$db_url" --username="$service_user" update