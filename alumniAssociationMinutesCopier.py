#!/usr/bin/env python3
from sys import exit
import urllib.parse
import http.client
import base64
import datetime

templatePath = "/Shared/Alumni Association/Association Meetings/2024_TEMPLATE.docx"
minutesFolder = "/Shared/Alumni Association/Association Meetings/Minutes"
localDebug = True

if not localDebug:
    with open("/opt/bots/password", "r") as passwordFile:
        if not passwordFile:
            print("This bot only works as root!")
            exit(0)
        botPassword = passwordFile.read()
else:
    botPassword = "password"

if not localDebug:
    with open("/opt/bots/agendaCreator/URLs/nextcloudURL.txt", "r") as ncUrlFile:
        if not ncUrlFile:
            print("Cannot find nextcloudURL.txt. Exiting.")
            exit(0)
        ncUrl = ncUrlFile.read()
else:
    ncUrl = "url"

minutesRequest = http.client.HTTPSConnection(ncUrl, "443")
print(ncUrl+urllib.parse.quote("remote.php/dav/files/bot"+minutesFolder))
minutesRequest.request(method="PROPFIND", url=ncUrl + urllib.parse.quote("remote.php/dav/files/bot" + minutesFolder), body="""
<?xml version="1.0" encoding="UTF-8"?>
  <d:propfind xmlns:d="DAV:">
    <d:prop xmlns:oc="http://owncloud.org/ns">
    </d:prop>
  </d:propfind>""", headers={"Authorization": "Basic "+base64.b64encode(b"bot:"+botPassword.encode()).decode()})
minutesResponse = minutesRequest.getresponse().read()
print(minutesResponse)

def getFileListFromResponse(response):
    return ["2024 August Minutes.docx", "2024 September Minutes.docx"]


fileList = getFileListFromResponse(minutesResponse)
newestDate = max(datetime.datetime.strptime(filename, "%Y %B Minutes.docx") for filename in fileList)
newFilename = (newestDate + datetime.timedelta(days=31)).strftime("%Y %B Minutes.docx")

minutesRequest = http.client.HTTPSConnection(ncUrl, "443")
print(ncUrl + urllib.parse.quote("remote.php/dav/files/bot" + templatePath))
minutesRequest.request(method="COPY",
                       url=ncUrl + urllib.parse.quote("remote.php/dav/files/bot" + minutesFolder + "/" + newFilename),
                       headers={"Authorization": "Basic " + base64.b64encode(b"bot:" + botPassword.encode()).decode(),
                                "Destination: ": ncUrl + urllib.parse.quote(
                                    "remote.php/dav/files/bot" + minutesFolder + "/" + newFilename)})
minutesRequest.close()

minutesRequest = http.client.HTTPSConnection(ncUrl, "443")
print(ncUrl + urllib.parse.quote(
    "remote.php/dav/files/bot" + minutesFolder + "/" + newFilename))
minutesRequest.request(method="PROPFIND", url=ncUrl + urllib.parse.quote("remote.php/dav/files/bot" + minutesFolder + "/" + newFilename), body="""
<?xml version="1.0" encoding="UTF-8"?>
   <d:propfind xmlns:d="DAV:">
     <d:prop xmlns:oc="http://owncloud.org/ns">
       <oc:fileid />
     </d:prop>
   </d:propfind>""", headers={"Authorization": "Basic "+base64.b64encode(b"bot:"+botPassword.encode()).decode()})
minutesResponse = minutesRequest.getresponse().read()
print(minutesResponse)
