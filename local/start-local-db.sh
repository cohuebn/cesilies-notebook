#!/usr/bin/env bash

dnsName=$1
certsDir=$2
caKey=$3
clusterNodes=$4

[[ -f "$certsDir/node.crt" ]] || cockroach cert create-node $(hostname) $(hostname -i) localhost 127.0.0.1 $dnsName --certs-dir="$certsDir" --ca-key="$caKey"
cockroach start --join="$clusterNodes" --certs-dir="$certsDir" --advertise-addr=$dnsName