#!/usr/bin/env bash

templatePath='/Shared/NewDrive/ALPHA SIG GENERAL/01_CHAPTER MEETINGS/AGENDAS/2024_SPRING/TEMPLATE.docx'
agendaFolder='/Shared/NewDrive/ALPHA SIG GENERAL/01_CHAPTER MEETINGS/AGENDAS/2024_SPRING'
minutesFolder='/Shared/NewDrive/ALPHA SIG GENERAL/01_CHAPTER MEETINGS/MEETING MINUTES/2024_SPRING'

# Grab the password for the bot from the password file (only root has access to it)
if ! password=$(cat /opt/bots/password); then
    echo 'This bot only works as root!'
    exit 1
fi

ncURL=$(cat /opt/bots/agendaCreator/URLs/nextcloudURL.txt)

# URL encode the folder paths for NextCloud using python's urllib, since that's already installed.
function urlencode {
    echo "$1" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()[:-1]))"
}
templatePath=$(urlencode "$templatePath")
agendaFolder=$(urlencode "$agendaFolder")
minutesFolder=$(urlencode "$minutesFolder")

# See https://docs.nextcloud.com/server/19/developer_manual/client_apis/WebDAV/basic.html for info on the NC API.
minutesResponse=$(curl -u "bot:$password" "${ncURL}remote.php/dav/files/bot$minutesFolder" -X PROPFIND --data \
'<?xml version="1.0" encoding="UTF-8"?>
  <d:propfind xmlns:d="DAV:">
    <d:prop xmlns:oc="http://owncloud.org/ns">
    </d:prop>
  </d:propfind>')


function urldecode {
    echo "$1" | python3 -c "import urllib.parse, sys; print(urllib.parse.unquote(sys.stdin.read()[:-1]))"
}

function getNewestFileDate {
    # The files are separated by newlines, this uses bash's IFS to split them.
    local files
    local IFS=$'\n'
    mapfile -t files <<< "$1"

    local i
    local latestDate=0
    for (( i=0; i<${#files[@]}; i++ )) ; do
        unquotedPath=$(urldecode "${files[i]}") # Undo the ncURL encoding
        filename=$(basename "$unquotedPath") # Extract filename
        dateStr=${filename%% *} # Pull out the date component of the filename
        unixTime=$(date --date="${dateStr//-/\/}" '+%s') # Replace - with / for date, then convert to unix timestamp
        # Update the latest date if needed
        if [ "$unixTime" -gt "$latestDate" ]; then
            latestDate="$unixTime"
        fi
    done
    echo "$latestDate"
}


function addAWeek {
    local unixTime="$1"
    unixTime=$(( unixTime + 604800 + 600 )) # Add a week plus 5 minutes to account for leap seconds
    date --date="@$unixTime" '+%-m-%-d-%-Y'
}

# Grab the files from NextCloud's API
minutesFiles=$(echo "$minutesResponse" | grep -E -o '/remote.php/dav/[^<]+' | grep -E -o '^.*\Minutes.docx$')

latestDate=$(getNewestFileDate "$minutesFiles") # Find the minutes with the latest date in the name
newAgendaName="$(addAWeek "$latestDate")%20Agenda.docx" # Add a week to the date to make the new name

# Copy the agenda over
curl -u "bot:$password" "${ncURL}remote.php/dav/files/bot$templatePath" -X COPY \
-H "Destination: ${ncURL}remote.php/dav/files/bot$agendaFolder/$newAgendaName" \
-H 'Overwrite: F'

# Get the share link
idResponse=$(curl -u "bot:$password" "${ncURL}remote.php/dav/files/bot$agendaFolder/$newAgendaName" \
 -X PROPFIND --data \
'<?xml version="1.0" encoding="UTF-8"?>
   <d:propfind xmlns:d="DAV:">
     <d:prop xmlns:oc="http://owncloud.org/ns">
       <oc:fileid />
     </d:prop>
   </d:propfind>')
id=$(echo "$idResponse" | grep -E -o '<oc:fileid>[^<]+' | cut -c 12-)
shareLink="${ncURL}f/$id"

# Send a reminder in the #directors channel.
curl "$(cat /opt/bots/agendaCreator/URLs/agendaDiscordURL.txt)" -X POST -H "Content-Type: application/json" \
--data "{\"content\": \"<@&626160984876384287> <@&626158522802896906> **The agenda for Monday's meeting has been generated! Please fill it out now:** $shareLink\"}"
