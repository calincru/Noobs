#!/bin/bash
if [[ $# != 2 ]]; then
    echo "Usage: ./get_map_list first_page_offset last_page_offset"
    exit 0
fi
first=$1
last=$2

numre='^[0-9]+$'
if ! [[ $first =~ $numre ]] || ! [[ $last =~ $numre ]]; then
    echo "Invalid argument"
    exit 1
fi

get_map_page_no() {
    wget "http://theaigames.com/competitions/warlight-ai-challenge-2/game-log/date%3C10-05-2015/$1" -O - 2>/dev/null
}
hrefre='http://theaigames\.com/competitions/warlight-ai-challenge-2/games/[0-9a-z]+'

for N in `seq $first $last`; do
    get_map_page_no $N | egrep -o "$hrefre"
done
