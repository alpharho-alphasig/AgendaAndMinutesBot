#!/usr/bin/env bash

currentSemester="$(jq -r '.currentSemester.year' /opt/bots/config.json)_$(jq -r '.currentSemester.season' /opt/bots/config.json)"
minutesFolder="$(jq -r '.minutesFolder' /opt/bots/config.json)/$currentSemester"
minutesFolder="$(jq -r '.minutesFolder' /opt/bots/config.json)/$currentSemester"
password=$(jq -r '.botPassword' /opt/bots/config.json)
ncURL=$(jq -r '.nextcloudURL' /opt/bots/config.json)
templatePath="$minutesFolder/TEMPLATE.docx"

# URL encode the folder paths for NextCloud using python's urllib, since that's already installed.
function urlencode {
    echo "$1" | python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.stdin.read()[:-1]))"
}
templatePath=$(urlencode "$templatePath")
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
newMinutesName="$(addAWeek "$latestDate")%20Minutes.docx" # Add a week to the date to make the new name
# Copy the minutes over
curl -u "bot:$password" "${ncURL}remote.php/dav/files/bot$templatePath" -X COPY \
-H "Destination: ${ncURL}remote.php/dav/files/bot$minutesFolder/$newMinutesName" \
-H 'Overwrite: F'

# Get the share link
idResponse=$(curl -u "bot:$password" --header 'OCS-APIRequest: true' "${ncURL}ocs/v2.php/apps/files_sharing/api/v1/shares?path=$minutesFolder/$newMinutesName&shareType=3&permissions=1" \
 -X POST)
shareLink=$(echo "$idResponse" | grep -E -o '<url>[^<]+' | cut -c 6-)
# Send a reminder in the #chapter-announcements channel.
curl "$(jq -r '.minutesDiscordURL' /opt/bots/config.json)" -X POST -H "Content-Type: application/json" \
--data "{\"content\": \"<@&626160984876384287> <@&626158522802896906> **The minutes for Monday's meeting has been generated! Please fill it out now:** $shareLink\"}"
