---
title: "Unblocking Firebase Network Traffic in Modified Android Applications"
date: 2021-04-03T17:16:08-07:00
---

Recently, I was interested in intercepting the network traffic between a third-party Android application and its remote servers. The only device I had available was my personal device, a non-rooted Pixel 3a. Normally, in these situations I would just use a Frida script to instrument the target app but that wasn't an option this time. In this case, I decided to take the old-school route of unpacking the APK, adding a lax `NetworkSecurityConfig`, rebuilding/signing, and adding the Burp CA to the user CA store. This is all pretty standard stuff, but when I launched the app, I noticed functionality was not working as expected. In Burp, I noticed little network traffic, but I saw HTTP POST requests going to `firebaseinstallations.googleapis.com/v1/projects/projectName/installations` which were receiving `403`s:

```
{
  "error": {
    "code": 403,
    "message": "Requests from this Android client application com.app.name are blocked.",
    "status": "PERMISSION_DENIED",
    "details": [
      {
        "@type": "type.googleapis.com/google.rpc.ErrorInfo",
        "reason": "API_KEY_ANDROID_APP_BLOCKED",
        "domain": "googleapis.com",
        "metadata": {
          "service": "firebaseinstallations.googleapis.com",
          "consumer": "projects/0000000000000"
        }
      }
    ]
  }
}
```

Not being very familiar with Firebase, I did some quick Googling and determined that this usually occurs when there is some sort of mismatch between your API and your application. That gave me a clue: Maybe my modifications to the APK are what caused the issues?

I noticed the HTTP request had a couple interesting headers:

```
POST /v1/projects/projectName/installations HTTP/1.1
Content-Type: application/json
Accept: application/json
Cache-Control: no-cache
X-Android-Package: com.app.name
X-Android-Cert: 6DFD10D5DB3B283B36881358316F7C7D92D3BE2D
x-goog-api-key: [39 character a-zA-Z0-9 string]
User-Agent: Dalvik/2.1.0 (Linux; U; Android 11; Pixel 3a Build/RQ2A.210305.006)
Host: firebaseinstallations.googleapis.com
Connection: close
Accept-Encoding: gzip, deflate
Content-Length: 129
```

The `X-Android-Cert` and `x-goog-api-key` were good places to start. The `x-goog-api-key` mapped to, as expected, the `google_api_key` and `google_crash_reporting_api_key` in `res/values/strings.xml`, so it was unlikely that was the culprit. The `X-Android-Cert` did not hit on any grep searches across the unpacked APK, but the name got me thinking that it might be the signature for the APK itself. It's pretty easy to check with `keytool`:

```
$ keytool -printcert -jarfile resigned.apk
Signer #1:

Signature:

Owner: ...
...
Certificate fingerprints:
	 SHA1: 6D:FD:10:D5:DB:3B:28:3B:36:88:13:58:31:6F:7C:7D:92:D3:BE:2D
	 SHA256: ....
Signature algorithm name: SHA256withRSA
Subject Public Key Algorithm: 2048-bit RSA key
Version: 3

Extensions: 

#1: ObjectId: 2.5.29.14 Criticality=false
SubjectKeyIdentifier [
KeyIdentifier [
...
]
]
```

As you can see, the SHA1 corresponds to the `X-Android-Cert` header. Now all you would need to do is grab the original SHA1 and replace it in Burp:

```
keytool -printcert -jarfile original.apk |grep SHA1|awk '{print $2}'|tr -d ':'
```

When I sent a request to the Burp Repeater and swapped out the `X-Android-Cert`, I received a different response:

```
HTTP/1.1 200 OK
Content-Type: application/json; charset=UTF-8
Date: ...
...
Content-Length: 575

{
  "name": "...",
  "fid": "...",
  "refreshToken": "...",
  "authToken": {
    "token": "...",
    "expiresIn": "604800s"
  }
}
```

Success! From here, I just created a Match and Replace rule in Burp to make my life easier. Hopefully this saves people a few clicks!