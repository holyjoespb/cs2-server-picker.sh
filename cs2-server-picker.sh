#!/usr/bin/env bash
set -e 
tmpjson=/tmp/cs2servers.json
tmplist=/tmp/cs2servers.list

function _get-json {
   curl -s -S "https://api.steampowered.com/ISteamApps/GetSDRConfig/v1?appid=730" -o $tmpjson
}

function _get-server-list {
   jq -r ".pops | keys[]" $tmpjson
}

function _get-server-ip-list {
   jq -r ".pops.$1.relays[].ipv4" $tmpjson 2> /dev/null
}

function _show-help {
    echo "Server picker script for CS2 matchmaking. Uses iptables rules, curl and jq."
    echo "  -l   list servers"
    echo "  -p   pick server, usage:"
    echo "       ${0##*/} -p tyo"
    echo "       or multpiple servers:"
    echo "       ${0##*/} -p hel,sto"
    echo "  -f   flush added iptables rules"
    exit 0
}

function _get-arguments() {
     if [ $# -eq 0 ];
     then
         _show-help
     else
         while getopts "lp:fh" opt
         do
            case $opt in
            l)      _list-servers
                    ;;
            p)      _add-rules "$OPTARG"
                    ;;
            f)      _flush-rules
                    ;;
            *)      _show-help
                    ;;
            esac
         done
     fi         
}

function _list-servers {
    echo  "downloading json..."
    _get-json
    echo "Servers:"
    _get-server-list | paste - - - - - - - -
}

function _add-rules {
   echo  "downloading json..."
   _get-json
   _get-server-list > $tmplist
   IFS=',' read -r -a arr <<< "$@"
   for i in "${arr[@]}"
   do
      grep -qFx "$i" $tmplist || ( echo "Error: \"$i\" is the incorrent server" ; exit 1 )
      sed -i "/^$i$/d" $tmplist
   done
   
   _flush-rules
   
   echo "adding rules..."
   set +e
   sudo iptables -N cs2-server-picker-rules
   sudo iptables -I INPUT -j cs2-server-picker-rules
   IFS=$'\n'
   while read -r srv
   do
       _get-server-ip-list "$srv" | while read -r srv_ip
       do
           sudo iptables -A cs2-server-picker-rules -s "$srv_ip" -j DROP
       done 
   done < "$tmplist"
}

function _flush-rules {
   echo "clearing rules..." 
   set +e
   sudo iptables -F cs2-server-picker-rules > /dev/null 2>/dev/null
   sudo iptables -D INPUT -j cs2-server-picker-rules > /dev/null 2>/dev/null
   sudo iptables -X cs2-server-picker-rules > /dev/null 2>/dev/null
}

_get-arguments "$@"
