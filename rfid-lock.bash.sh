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

# Get the API keys. The following are expected to be set:
#   API_KEY:     the BBMS API key
#   DEVICE_NAME: the BBMS device name
#   DISCORD_URL: the Discord POST URL
source /root/keys

# Source the previous key cache:
KEY_CACHE="/root/bbms-key-cache"
source ${KEY_CACHE} || true


# POST a file to the server and store the result in RTN
# argument list is the URL suffix followed by the text to POST
function contact_server
{
    URL_PART="$1"
    shift
    RTN=$( wget -q -o- --post-data="$@" \
        --header="Content-Type:application/json" \
        --header="Accept: application/json" \
        --header="ApiKey: ${API_KEY}" \
        --server-response \
        https://bbms.buildbrighton.com/acs/${URL_PART} \
        | sed -n 's|.*HTTP/[^ ]* \([0-9]*\).*|\1|p'
    )
    unset RESPONSE_OK
    OFFLINE=1

    case "${RTN}" in
    2*)
        RESPONSE_OK=1
        ;;
    4*)
        unset OFFLINE
        ;;
    5*)
        ;;
    *)
        if ncat -z bbms.buildbrighton.com 443 2>/dev/null; then
            unset OFFLINE
        fi
        ;;
    esac

    printf '"%s" << "%s"\n' ${URL_PART} "$@"
    printf '.. "%s" (%s, %s)\n' "${RTN}" "${RESPONSE_OK}" "${OFFLINE}"
}

function post_discord
{
    wget -q -O- \
        --post-data="{ \"content\": \"$1 is in the space!\" }" \
        --header="Content-Type:application/json" \
        ${DISCORD_URL}
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
    n=$( printf "%010x" "$1" )
    i=0
    sum=0
    while [ $i -lt ${#n} ]; do
        sum=$(( ${sum} ^ 16#${n:$i:2} ))
        i=$(( ${i} + 2 ))
    done
    printf "%010X%02X\n" "$1" $sum
}

function open_door
{
    echo opening door to $@
    echo "1" > "${GPIO_DEV}"
    sleep 2
    echo "0" > "${GPIO_DEV}"
}

function sync_cache
{
    env | sed -n 's/^CACHE_/export CACHE_/p' > ${KEY_CACHE}
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
                #contact_server "{\"service\":\"entry\", \"device\":\"neil-test\", \"message\":\"lookup\", \"tag\":\"${T}\"}"
                contact_server activity "{\"tagId\":\"${T}\", \"device\":\"${DEVICE_NAME}\", \"occurredAt\":\"$(date +%s)\"}"
                # if the server is down, just give up now
                if [ -n "${OFFLINE}" ]; then
                    echo Server is down. So sorry, can\'t grant access right now
                    break
                fi
                if [ -n "${RESPONSE_OK}" ]; then
                    # found it - cache this value for next time
                    MEMBER_NAME="$(get_string name)"
                    eval "export CACHE_${KEY_CODE}=${T}"
                    echo caching "CACHE_${KEY_CODE}=${T}"
                    sync_cache
                    open_door "${MEMBER_NAME}"
                    post_discord "${MEMBER_NAME}"
                    break
                else
                    echo access denied
                fi
            done
        else
            echo I know you ${KEY_CODE}...
            # key is in cache. if server was not up recently, grant access immediately
            if [ -n "$OFFLINE" ]; then
                open_door ${LONG_FORM}
                # then do a courtesy check with server
                contact_server activity "{\"tagId\":\"${LONG_FORM}\", \"device\":\"${DEVICE_NAME}\", \"occurredAt\":\"$(date +%s)\"}"
                post_discord "key fob #${KEY_CODE}"
            else
                # otherwise check with the server first
                contact_server activity "{\"tagId\":\"${LONG_FORM}\", \"device\":\"${DEVICE_NAME}\", \"occurredAt\":\"$(date +%s)\"}"
                if [ -n "${RESPONSE_OK}" ]; then
                    MEMBER_NAME="$(get_string name)"
                    open_door ${LONG_FORM}
                    post_discord "${MEMBER_NAME}"
                else
                    echo access denied
                fi
            fi
            # if the server said no, then remove key from cache
            if ! [ -n "${RESPONSE_OK}" ] && ! [ -n "${OFFLINE}" ]; then
                echo access revoked!
                eval "unset CACHE_${KEY_CODE}"
                echo uncaching "CACHE_${KEY_CODE}"
                sync_cache
            fi
        fi
    else
        test $(( ${LOOP_TIME} + ${HEARTBEAT_RATE} )) -gt "$(date +%s)" && exit 1

        # timed out whilst waiting - send a heartbeat
        # echo Idle for $((${HEARTBEAT_RATE} / 60)) mins - sending a heartbeat message to server
        contact_server node/heartbeat
    fi
done
