#!/usr/bin/env bash
# HiveOS h-stats.sh for pearl GPU miner

. `dirname $BASH_SOURCE`/h-manifest.conf

LOG_FILE="$CUSTOM_LOG_BASENAME.log"

khs=0
stats=""

if [[ -f $LOG_FILE ]]; then
    log_age=$(( $(date +%s) - $(stat -c %Y "$LOG_FILE") ))

    if (( log_age <= 60 )); then

        tail_buf=$(tail -n 150 "$LOG_FILE")

        #
        # ===== LAST-SEEN PER GPU HASH (FIXED) =====
        #
        device_hash_tsv=$(
            awk '
            /event=large\.progress\.device/ {

                dev=""
                rate=""

                for (i=1;i<=NF;i++) {

                    if ($i ~ /^device=/) {
                        split($i,a,"=")
                        dev=a[2]
                    }

                    if ($i ~ /^proof_per_sec=/) {
                        rate=$i
                        sub(/^proof_per_sec="/,"",rate)
                        gsub(/"/,"",rate)
                    }
                }

                if (dev != "" && rate != "") {
                    rates[dev]=rate
                }
            }

            END {
                for (dev in rates)
                    printf "%s\t%s\n", dev, rates[dev]
            }' "$LOG_FILE" | sort -n -k1,1
        )

        #
        # TOTAL HASH (T/s -> sum)
        #
        proof_per_sec=0

        if [[ -n $device_hash_tsv ]]; then
            proof_per_sec=$(
                echo "$device_hash_tsv" |
                awk -F'\t' '
                {
                    rate=$2
                    sub(/[[:space:]]*T\/s$/,"",rate)
                    sum += rate
                }
                END {
                    printf "%.2f", sum
                }'
            )
        fi

        #
        # khs
        #
        khs=$(awk -v p="$proof_per_sec" 'BEGIN{printf "%.3f", p * 1000000000}')

        #
        # TELEMETRY (temp/fan/power)
        #
        dev_tsv=$(echo "$tail_buf" \
            | awk '/event=device\.stats/{
                idx=""; t=""; f=""; p=""

                for (i=1;i<=NF;i++) {

                    if ($i ~ /^index=/) {
                        split($i,a,"=")
                        idx=a[2]
                    }

                    if ($i ~ /^temperature_c=/) {
                        split($i,a,"=")
                        t=a[2]
                    }

                    if ($i ~ /^fan_pct=/) {
                        split($i,a,"=")
                        f=a[2]
                    }

                    if ($i ~ /^power_w=/) {
                        split($i,a,"=")
                        p=a[2]
                    }
                }

                if (idx!="") {
                    temp[idx]=t
                    fan[idx]=f
                    pow[idx]=p
                }
            }

            END {
                for (k in temp)
                    printf "%s\t%s\t%s\t%s\n",
                        k,temp[k],fan[k],pow[k]
            }' | sort -n -k1,1)

        temp_json="[]"
        fan_json="[]"
        power_json="[]"

        if [[ -n $dev_tsv ]]; then

            temp_json=$(
                echo "$dev_tsv" | awk -F'\t' '{print $2}' | jq -Rn '[inputs|tonumber? // 0]'
            )

            fan_json=$(
                echo "$dev_tsv" | awk -F'\t' '{print $3}' | jq -Rn '[inputs|tonumber? // 0]'
            )

            power_json=$(
                echo "$dev_tsv" | awk -F'\t' '{print $4}' | jq -Rn '[inputs|tonumber? // 0]'
            )
        fi

        #
        # per-GPU hs[]
        #
        if [[ -n $device_hash_tsv ]]; then

            hs_json=$(
                echo "$device_hash_tsv" |
                awk -F'\t' '
                {
                    rate=$2
                    sub(/[[:space:]]*T\/s$/,"",rate)
                    printf "%.3f\n", rate * 1000000000
                }' |
                jq -Rn '[inputs|tonumber? // 0]'
            )

        else
            hs_json='[]'
        fi

        #
        # uptime
        #
        first_ts=$(grep -m1 -oE 'ts=[0-9T:.-]+' "$LOG_FILE" 2>/dev/null | head -n1 | cut -d= -f2)

        uptime_s=0

        if [[ -n $first_ts ]]; then
            start_epoch=$(date -d "${first_ts%.*}" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)

            (( start_epoch > 0 )) && uptime_s=$(( now_epoch - start_epoch ))
            (( uptime_s < 0 )) && uptime_s=0
        fi

        ver="pearl"

        stats=$(
            jq -nc \
                --argjson hs "$hs_json" \
                --arg hs_units "khs" \
                --argjson temp "$temp_json" \
                --argjson fan "$fan_json" \
                --argjson power "$power_json" \
                --argjson uptime "$uptime_s" \
                --arg algo "pearl" \
                --arg ver "$ver" \
                --arg ac "$proof_per_sec" \
                '{
                    hs:$hs,
                    hs_units:$hs_units,
                    temp:$temp,
                    fan:$fan,
                    power:$power,
                    uptime:$uptime,
                    ar:[($ac|tonumber),0],
                    algo:$algo,
                    ver:$ver
                }'
        )

    fi
fi

[[ -z $khs ]] && khs=0

[[ -z $stats ]] && \
stats='{"hs":[],"hs_units":"khs","temp":[],"fan":[],"power":[],"uptime":0,"ar":[0,0],"algo":"pearl","ver":"pearl"}'