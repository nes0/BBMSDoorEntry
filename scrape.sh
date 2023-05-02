#! /bin/bash

wget --load-cookies cookies.txt wget https://bbms.buildbrighton.com/account\?showLeft\=0

rm -f keys.txt
for pg in $( cat account\?showLeft=0 | sed -n 's|.*\(/account/[0-9]*\)".*|\1|p' ); do
	wget --load-cookies cookies.txt https://bbms.buildbrighton.com${pg} -O- \
	| sed -n 's|.*<p class="form-control-static">\([0-9A-Z]*\) <small>.*|\1|p' \
	>> keys.txt
done

cat keys.txt | while read hex_key; do
	printf "export CACHE_%010d=${hex_key}\n" 0x${hex_key:2:8}
done > bbms-key-cache

cat keys.txt | sed -n 's/\([0-9A-F][0-9A-F]\).*/\100000000/p' | sort | uniq -c \
	| sort -nr | cut -c 9-
