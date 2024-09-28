#!/usr/bin/env bash

currentSemester="$(jq -r '.currentSemester.year' /opt/bots/config.json)_$(jq -r '.currentSemester.season' /opt/bots/config.json)"
agendaFolder="$(jq -r '.agendaFolder' /opt/bots/config.json)/$currentSemester"
minutesFolder="$(jq -r '.minutesFolder' /opt/bots/config.json)/$currentSemester"
password=$(jq -r '.botPassword' /opt/bots/config.json)
ncURL=$(jq -r '.nextcloudURL' /opt/bots/config.json)

# URL encode the folder paths for NextCloud using python's urllib, since that's already installed.
function urlencode {
    echo "$1" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()[:-1]))"
}
agendaFolder=$(urlencode "$agendaFolder")
minutesFolder=$(urlencode "$minutesFolder")

# See https://docs.nextcloud.com/server/19/developer_manual/client_apis/WebDAV/basic.html for info on the NC API.
agendaResponse=$(curl -u "bot:$password" "${ncURL}remote.php/dav/files/bot$agendaFolder" -X PROPFIND --data \
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
        if [ "$unixTime" -gt "$latestDate" ]; then
            latestDate="$unixTime"
        fi
    done
    echo "$latestDate"
}

# Grab the files from NextCloud's API
agendaFiles=$(echo "$agendaResponse" | grep -E -o '/remote.php/dav/[^<]+' | grep -E -o '^.*\Agenda.docx$')

# Find the minutes with the latest date in the name
agendaDate=$(date --date="@$(getNewestFileDate "$agendaFiles")" '+%-m-%-d-%-Y')
agendaName="$agendaDate%20Agenda.docx"
newMinutesName="$agendaDate%20Minutes.docx"

# Copy the minutes over.
curl -u "bot:$password" "${ncURL}remote.php/dav/files/bot$agendaFolder/$agendaName" \
-X COPY -H "Destination: ${ncURL}remote.php/dav/files/bot$minutesFolder/$newMinutesName"

# Get the share link
idResponse=$(curl -u "bot:$password" "${ncURL}remote.php/dav/files/bot$minutesFolder/$newMinutesName" \
-X PROPFIND --data \
'<?xml version="1.0" encoding="UTF-8"?>
   <d:propfind xmlns:d="DAV:">
     <d:prop xmlns:oc="http://owncloud.org/ns">
       <oc:fileid />
     </d:prop>
   </d:propfind>')
id=$(echo "$idResponse" | grep -E -o '<oc:fileid>[^<]+' | cut -c 12-)
shareLink="${ncURL}f/$id"

# Send a message on discord in #chapter-announcements.
curl "$(jq -r '.minutesDiscordURL' /opt/bots/config.json)" -X POST -H "Content-Type: application/json" \
--data "{\"content\": \"<@&626070887166377984> **Here are this week's meeting minutes:** $shareLink\"}"
