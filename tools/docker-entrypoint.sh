#!/bin/bash

cat <<-EOF > "$LIGHTNINGD_DATA/config"
${LIGHTNINGD_OPT}
EOF

: "${EXPOSE_TCP:=false}"

NETWORK=$(sed -n 's/^network=\(.*\)$/\1/p' < "$LIGHTNINGD_DATA/config")
CHAIN=$(sed -n 's/^chain=\(.*\)$/\1/p' < "$LIGHTNINGD_DATA/config")

sed -i '/^chain=/d' "$LIGHTNINGD_DATA/config"

REPLACEDNETWORK="";
if [ "$CHAIN" == "btc" ]; then
    if [ "$NETWORK" == "mainnet" ]; then
        REPLACEDNETWORK="bitcoin"
    fi
fi

if [ "$CHAIN" == "ltc" ]; then
    if [ "$NETWORK" == "mainnet" ]; then
        REPLACEDNETWORK="litecoin"
    fi
    if [ "$NETWORK" == "testnet" ]; then
        REPLACEDNETWORK="litecoin-testnet"
    fi
    if [ "$NETWORK" == "regtest" ]; then
        echo "REGTEST NOT AVAILABLE FOR LTC"
        exit
    fi
fi

if [ $TRACE_TOOLS ]; then
echo "Trace tools detected, installing sample.sh..."
echo 0 > /proc/sys/kernel/kptr_restrict
echo "
LIGHTNING_PROCESSES=\$(pidof lightningd lightning_chann lightning_closi lightning_gossi lightning_hsmd lightning_oncha lightning_openi lightning_hsmd lightning_gossipd lightning_channeld  | sed -e 's/\s/,/g')
perf record -F 99 -g -a --pid \$LIGHTNING_PROCESSES -o "$TRACE_LOCATION/perf.data" -- sleep 60
perf script -i "$TRACE_LOCATION/perf.data" > "$TRACE_LOCATION/output.trace"
cd /FlameGraph
./stackcollapse-perf.pl "$TRACE_LOCATION/output.trace" > "$TRACE_LOCATION/output.trace.folded"
./flamegraph.pl "$TRACE_LOCATION/output.trace.folded" > "$TRACE_LOCATION/output.trace.svg"
" > /usr/bin/sample.sh
chmod +x /usr/bin/sample.sh
fi

if [[ $REPLACEDNETWORK ]]; then
    sed -i '/^network=/d' "$LIGHTNINGD_DATA/config"
    echo "network=$REPLACEDNETWORK" >> "$LIGHTNINGD_DATA/config"
    echo "Replaced network $NETWORK by $REPLACEDNETWORK in $LIGHTNINGD_DATA/config"
fi

if [ "$EXPOSE_TCP" == "true" ]; then
    lightningd &

    echo "C-Lightning starting"
    while read -r i; do if [ "$i" = "lightning-rpc" ]; then break; fi; done \
    < <(inotifywait  -e create,open --format '%f' --quiet "$LIGHTNINGD_DATA" --monitor)
    echo "C-Lightning started"

    socat "TCP4-listen:$LIGHTNINGD_PORT,fork,reuseaddr" "UNIX-CONNECT:$LIGHTNINGD_DATA/lightning-rpc"
else
    lightningd
fi
