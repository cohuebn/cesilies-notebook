#!/usr/bin/env bash

splitOnCommas() {
    local originalIfs=$IFS
    IFS=,
    local items=($1)
    for item in "${items[@]}"; do
        echo "$item"
    done
    IFS=$originalIfs
}
dbNodes=($(splitOnCommas $1))
dbPort=$2
certsDir=$3
dbName=$4
serviceUser=$5
serviceUserPassword=$6
changelogPath=$7

# Validate inputs
if [ ${#dbNodes[@]} -eq 0 ]; then
    echo "No database nodes provided; cannot run without any database nodes"
    exit 1
fi

dbObjectPattern='^([0-9a-z]+_*)*[0-9a-z]+$'
if ! [[ $dbName =~ $dbObjectPattern ]]; then
    echo "Database name must be all-lowercase letters (a-z, 0-9, and underscore allowed]"
    exit 1
fi

if ! [[ $serviceUser =~ $dbObjectPattern ]]; then
    echo "Service user must be all-lowercase letters (a-z, 0-9, and underscore allowed]"
    exit 1
fi

# Create the root and service user's certs
[ ! -f "$certsDir/client.root.crt" ] && cockroach cert create-client root --ca-key="$certsDir/ca.local.key" --certs-dir=$certsDir
[ ! -f "$certsDir/client.$serviceUser.crt" ] && cockroach cert create-client $serviceUser --ca-key="$certsDir/ca.local.key" --certs-dir=$certsDir --also-generate-pkcs8-key

# Run a sql command to check if each node in the cluster has been initialized; if not initialize it
for dbNode in $dbNodes; do
    echo "Ensuring DB node $dbNode is initialized"
    cockroach sql --certs-dir="$certsDir" --host "$dbNode" --execute="select 1" \
        || cockroach init --certs-dir="$certsDir" --host "$dbNode"
done

# Ensure the database and schema migration user exist to allow further schema evolution
deployerRole='cesilies_notebook_deployer'
dbInitSql=$(cat <<EOF
CREATE DATABASE IF NOT EXISTS $dbName;
CREATE ROLE IF NOT EXISTS $deployerRole WITH CREATEDB;
GRANT ALL ON DATABASE $dbName TO $deployerRole;
CREATE USER IF NOT EXISTS $serviceUser WITH PASSWORD '$serviceUserPassword';
GRANT $deployerRole TO $serviceUser;
EOF
)
firstDbNode=${dbNodes[0]}
echo "Running migrations against db node: $firstDbNode"
cockroach sql --certs-dir="$certsDir" --host "$firstDbNode" --execute "$dbInitSql"

dbUrl="jdbc:postgresql://$firstDbNode:$dbPort/$dbName?sslmode=verify-full&sslrootcert=$certsDir/ca.crt&sslkey=$certsDir/client.$serviceUser.key.pk8&sslcert=$certsDir/client.$serviceUser.crt"
echo "Running Liquibase using DB URL: $dbUrl"
liquibase --changelog-file="$changelogPath" --url="$dbUrl" --username="$serviceUser" update