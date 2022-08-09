#! /bin/bash --debug

HEARTBEAT_RATE=900  # seconds

# A list of kay prefixes to test against BBMS.
# (BBMS stores the fob's vendor ID as well as the key number. Our USB reader
#  doesn't give us this extra info, so we have to guess it.)
PREFIXES="
    BB00000000
    1900000000
    1700000000
    7000000000
    7900000000
    1600000000
    8200000000
    2800000000
    1E00000000
    1800000000
    0600000000
    0000000000
"

# OpenWRT hack: this is the device which effects a GPIO for the door actuator
GPIO_DEV="/sys/class/leds/red:broadband/brightness"


# TODO: replace these values with the real BBMS device name and API Key!
DEVICE_NAME=my_device
API_KEY=my_api_key



# POST a file to the server and store the result in RTN
# argument list is the URL suffix followed by the text to POST
function contact_server
{
    URL_PART="$1"
    shift
    RTN=$( wget -q -O- --post-data="$@" \
        --header="Content-Type:application/json" \
        --header="Accept: application/json" \
        --header="ApiKey: ${API_KEY}" \
        https://bbms.buildbrighton.com/acs/${URL_PART} \
    ) && RESPONSE_OK=1 || unset RESPONSE_OK
    if [ -z "${RESPONSE_OK}" ]; then
        if ncat -z bbms.buildbrighton.com 443 2>/dev/null; then
            unset OFFLINE
        else
            OFFLINE=1
        fi
    else
        unset OFFLINE
    fi

    printf 'ernie: "%s" > "%s"\n' "$@" ${URL_PART}
    printf 'bert:  "%s" (code: %s, OFFLINE:%s)\n' "${RTN}" "${RESPONSE_OK}" "${OFFLINE}"
}

# extract a quoted string value for a given key from RTN
function get_string
{
    grep -Po "\"$1\":.*?[^\\\\]\"[,}]" <<<${RTN} | head -c-2 | cut -d: -f2 | cut -d\" -f2
}

# extract a non-quoted value for a given key from RTN
function get_number
{
    grep -Po "\"$1\":[0-9]*?[,}]" <<<${RTN} | head -c-2 | cut -d: -f2
}
# append a two digit sum to the end of the given number and print as hex
function append_checksum
{
    n=$( printf "%x" "$1" )
    i=0
    sum=0
    while [ $i -lt ${#n} ]; do
        sum=$(( ${sum} ^ 16#${n:$i:2} ))
        i=$(( ${i} + 2 ))
    done
    printf "%X%02X\n" "$1" $sum
}

function open_door
{
    echo opening door to $@
    echo "1" > "${GPIO_DEV}"
    sleep 2
    echo "0" > "${GPIO_DEV}"
}

# inform server of our start up
contact_server node/boot

while true; do

    LOOP_TIME="$( date +%s )"

    if read -p "Enter key code: " -t ${HEARTBEAT_RATE} KEY_CODE; then
        # check whether the entered code was cached
        eval LONG_FORM=\$CACHE_${KEY_CODE}
        if [ -z "$LONG_FORM" ]; then
            # not cached - try spamming server with all known prefixes
            for PREFIX in ${PREFIXES}; do
                T=$( append_checksum $(( 16#${PREFIX} + 10#${KEY_CODE} )) )
                contact_server activity "{\"tagId\":\"${T}\", \"device\":\"${DEVICE_NAME}\", \"occuredAt\":\"$(date +%s)\"}"
                # if the server is down, just give up now
                if [ -n "${OFFLINE}" ]; then
                    echo Server is down. So sorry, can\'t grant access right now
                    break
                fi
                if [ -n "${RESPONSE_OK}" ]; then
                    # found it - cache this value for next time
                    eval "CACHE_${KEY_CODE}=${T}"
                    echo caching "CACHE_${KEY_CODE}=${T}"
                    open_door "$(get_string name)"
                    break
                else
                    echo access denied
                fi
            done
        else
            echo I know you...
            # key is in cache. if server was not up recently, grant access immediately
            if [ -n "$OFFLINE" ]; then
                open_door ${LONG_FORM}
                # then do a courtesy check with server
                contact_server activity "{\"tagId\":\"${LONG_FORM}\", \"device\":\"${DEVICE_NAME}\", \"occuredAt\":\"$(date +%s)\"}"
            else
                # otherwise check with the server first
                contact_server activity "{\"tagId\":\"${LONG_FORM}\", \"device\":\"${DEVICE_NAME}\", \"occuredAt\":\"$(date +%s)\"}"
                if [ -n "${RESPONSE_OK}" ]; then
                    open_door ${LONG_FORM}
                else
                    echo access denied
                fi
            fi
            # if the server said no, then remove key from cache
            if ! [ -n "${RESPONSE_OK}" ] && ! [ -n "${OFFLINE}" ]; then
                echo access revoked!
                eval unset CACHE_${KEY_CODE}
                echo uncaching "CACHE_${KEY_CODE}"
            fi
        fi
    else
        test $(( ${LOOP_TIME} + ${HEARTBEAT_RATE} )) -gt "$(date +%s)" && exit 1

        # timed out whilst waiting - send a heartbeat
        echo Idle for $((${HEARTBEAT_RATE} / 60)) mins - sending a heartbeat message to server
        contact_server node/heartbeat
    fi
done
