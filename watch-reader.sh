#! /bin/bash -e

MYDIR=$( cd $(dirname "$0") && pwd )

FIFO=/var/run/fob-reader

test -z ${INPUT_EVENTS+x} && INPUT_EVENTS=/dev/input/event0

mkfifo ${FIFO} || true

trap reap_children SIGINT SIGTERM

function reap_children
{
	kill ${USB_EVENT_PID} > /dev/null || true
	kill ${LOCK_SCRIPT_PID} > /dev/null || true
}

while true; do

	${MYDIR}/grab-hid ${INPUT_EVENTS} \
		1> ${FIFO} &
	USB_EVENT_PID=$!

	( cat ${FIFO} | ${MYDIR}/rfid-lock.bash.sh ) &
	LOCK_SCRIPT_PID=$!

	while test -x /proc/${USB_EVENT_PID} \
		&& test -x /proc/${LOCK_SCRIPT_PID}; do

		sleep 10
	done

	reap_children

	sleep 10

done
