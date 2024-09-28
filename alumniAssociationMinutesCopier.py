#!/usr/bin/env python3
from sys import exit
from urllib.parse import quote, unquote
import http.client
import base64
import datetime
import xml.etree.ElementTree as etree
import json

with open("/opt/bots/config.json", "r") as configFile:
    config = json.load(configFile)

# Paths
templatePath = config["aaFolder"] + "/" + str(config["currentSemester"]["year"]) + "_TEMPLATE.docx"
minutesFolder = config["aaMinutesFolder"]

# Utility functions

def substringAfterLast(s: str, delim: str):
    i = s.rfind(delim)
    return s[i+len(delim):] if i != -1 else s

def substringBetween(s: str, start: str, end: str):
    i1 = s.find(start)
    i2 = s.find(end)
    if i1 != i2 != -1:
        return s[i1+len(start):i2]
    elif i1 == i2 == -1:
        return s
    elif i1 == -1:
        return s[:i2]
    return s[i1+len(start):]

def getFileListFromResponse(response):
    xml: etree.Element = etree.fromstring(response)
    responses = [x for x in xml.iterfind("d:response", {"d": "DAV:"})]
    results = [[x for x in g][0] for g in [x.iterfind("d:href", {"d": "DAV:"}) for x in responses]]
    return [unquote(substringAfterLast(result.text, "/")) for result in results if not result.text.endswith("/")]

# Variables I did not want to put on GitHub
botPassword = config["botPassword"]
ncUrl = config["nextcloudURL"]

# List all the files in the minutes directory
minutesRequest = http.client.HTTPSConnection(ncUrl[8:-1], 443)
minutesRequest.request(method="PROPFIND", url=ncUrl + quote("remote.php/dav/files/bot" + minutesFolder), body=
"""<?xml version="1.0" encoding="UTF-8"?>
  <d:propfind xmlns:d="DAV:">
    <d:prop xmlns:oc="http://owncloud.org/ns">
    </d:prop>
  </d:propfind>""", headers={"Authorization": "Basic "+base64.b64encode(b"bot:"+botPassword.encode()).decode(), "Content-Type": "application/xml"})
minutesResponse = minutesRequest.getresponse().read()
fileList = getFileListFromResponse(minutesResponse)

# Find the newest file in the list by parsing its name as a date
newestDate, newestFilename = max((datetime.datetime.strptime(filename, "%Y %B Minutes.docx"), filename) for filename in fileList)
nextMonth = newestDate + datetime.timedelta(days=31)

# If the next minutes would be created more than a month from now
# (I.E: It's February '24 and it wants to make June '24 minutes), then exit
if nextMonth >= (datetime.datetime.now() + datetime.timedelta(days=31)):
    print("Meeting minutes should already exist?")
    exit(0)

# Convert the date for next month back into a filename
newFilename = nextMonth.strftime("%Y %B Minutes.docx")

# Copy the template to make the new minutes
minutesRequest.request(method="COPY",
                       url=ncUrl + quote("remote.php/dav/files/bot" + templatePath),
                       headers={"Authorization": "Basic " + base64.b64encode(b"bot:" + botPassword.encode()).decode(),
                                "Destination": ncUrl + quote("remote.php/dav/files/bot" + minutesFolder + "/" + newFilename)})
minutesRequest.getresponse().close() # You have to close or read the response to re-use the request object

# Get the file ID of the new minutes so we can get the share link
minutesRequest.request(method="PROPFIND", url=ncUrl + quote("remote.php/dav/files/bot" + minutesFolder + "/" + newFilename), body=
"""<?xml version="1.0" encoding="UTF-8"?>
   <d:propfind xmlns:d="DAV:">
     <d:prop xmlns:oc="http://owncloud.org/ns">
       <oc:fileid />
     </d:prop>
   </d:propfind>""", headers={"Authorization": "Basic "+base64.b64encode(b"bot:"+botPassword.encode()).decode()})
minutesResponse = minutesRequest.getresponse().read()
fileId = substringBetween(str(minutesResponse), "<oc:fileid>", "</oc:fileid>")
shareLink= ncUrl + "f/" + fileId

# Send a message on discord in officer #announcements.
discordWebhookUrl = config["minutesAADiscordURL"]
print("<@&1130649672525021294> **Here are next month's meeting minutes:** "+ shareLink)
minutesRequest = http.client.HTTPSConnection("discord.com", 443)
minutesRequest.request(method="POST", url=discordWebhookUrl, headers={"Content-Type": "application/json"},
                       body="{\"content\": \"<@&1130649672525021294> **Here are next month's meeting minutes:** "+ shareLink +"\"}")
minutesResponse = minutesRequest.getresponse().close()

