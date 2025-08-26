# terminal-notifier

[![GitHub release](https://img.shields.io/github/release/jklap/terminal-notifier.svg)](https://github.com/jklap/terminal-notifier/releases)

terminal-notifier is a command-line tool to send macOS User Notifications

This fork also includes functionality from [Alerter](https://github.com/vjeantet/alerter)

Alerts are OS X notifications that stay on screen unless dismissed.

The program ends when the notification is activated or closed, writing the activated value to output (stdout), or a json object to describe the alert event.

4 kinds of alert notification can be triggered:
- Basic Alert
- Responsive Alert
- Reply Alert
- Actions Alert

If you'd like notifications to stay on the screen until dismissed, go to System Preferences -> Notifications -> terminal-notifier and change the style from Banners to Alerts. You cannot do this on a per-notification basis.

## Basic alert
This is just a normal Alert notification.

Once the notification has been sent, the program will end.

## Responsive Alert
This is an Alert notification that supports an action when the user confirms the Alert. Currently supporting the following actions:
- Active an application
- Open a URL
- Execute a shell command

Once the notification has been sent, the program will end (but before any action taken by the user)

## Reply alert
Open an Alert notification and display a "Reply" button, which opens a text input.

The program ends and will return the result when a response is typed into the reply field.

## Actions alert
Open an Alert notification displays one or more actions to click on.

The program ends and will return the result of the choosen "action"

## Features

* Customize the alert's icon, title, subtitle, or image.
* Capture text typed by user in the reply type alert.
* Support for a timeout: automatically close the alert notification after a delay.
* Change the close button's label.
* Change the actions dropdown's label.
* Play a sound while delivering the alert notification.
* Return the value of the alert's event (closed, timeout, replied, activated, etc) in plain text or json
* Close the alert notification on SIGINT, SIGTERM.

## Installation

### Download

TODO: provide release binaries

Prebuilt binaries are available from the
[releases section](https://github.com/jklap/terminal-notifier/releases).

### Building and Installation

If you need to rebuild the application:

Build using Xcode (defaults to building debug version):
```bash
xcodebuild \
    CODE_SIGN_IDENTITY="-" \
    build
```

The binary will be available at:
```
build/Debug/terminal-notifier.app/Contents/MacOS/terminal-notifier
```

Building the release version:
```bash
xcodebuild \
    -configuration Release
```

### Path

Note that due to code-signing requirements, the binary must be used from within the application, ie you have to call the binary _inside_ the application bundle.

For instance, if the application has been installed to /Applications then you would call it like:
```bash
/Applications/terminal-notifier.app/Contents/MacOS/terminal-notifier -help
```

You can also use 
```bash
# verify it's location
mdfind "kMDItemCFBundleIdentifier == 'com.halfsane.terminal-notifier'"

# add it to PATH
export PATH=$PATH:$(mdfind "kMDItemCFBundleIdentifier == 'com.halfsane.terminal-notifier'")/Contents/MacOS

# or just create a shell alias
alias terminal-notifier=$(mdfind "kMDItemCFBundleIdentifier == 'com.halfsane.terminal-notifier'")/Contents/MacOS/terminal-notifier
```

## Usage

Note: the below examples all assume that you have set up your PATH or an alias so that you can call `terminal-notifier` directly

```bash
terminal-notifier -[message|group|list] [VALUE|ID|ID] [options]
```

## Example Uses

### Basic usage
```bash
terminal-notifier \
    -title 'My App' \
    -message 'This is the message' \
    -sound default
```

### Display message piped data:
```bash
echo 'Piped message!' | terminal-notifier
```

![Example 1](assets/Example_1.png)

### Multiple actions and custom dropdown list:
```bash
terminal-notifier \
    -message 'Deploy now on UAT?' \
    -actions Now,'Later today','Tomorrow' \
    -dropdownLabel 'When?'
```

### Yes or No (close notification is same as "No"):
```bash
terminal-notifier \
    -title 'Project X' \
    -subtitle 'New tag detected' \
    -message 'Deploy now on UAT?' \
    -closeLabel No \
    -actions Yes,Maybe \
    -json
```

```bash
terminal-notifier \
    -title 'Project X' \
    -subtitle 'New tag detected' \
    -message 'Deploy now on UAT?' \
    -actions Yes,No \
    -json
```

![Example 2](assets/Example_2.png)

### Use a custom icon:
```bash
terminal-notifier \
    -title 'Project X' \
    -message 'Finished' \
    -appIcon 'http://vjeantet.fr/images/logo.png'
```

### Use an image in the content:

```bash
terminal-notifier \
    -title 'Project X' \
    -message 'Finished' \
    -contentImage 'http://vjeantet.fr/images/logo.png'
```

Note: we need to create a copy of the image as it will be moved into the Notification
```bash
cp assets/logo.png ./logo.png

terminal-notifier \
    -title 'Project X' \
    -message 'Finished' \
    -contentImage "file://$(pwd)/logo.png"
```

![Example 3](assets/Example_3.png)

### Open an URL when the notification is clicked:
```bash
terminal-notifier \
    -title '💰' \
    -message 'Open the Apple stock price' \
    -open 'https://www.google.com/finance/quote/AAPL:NASDAQ'
```

![Example 4](assets/Example_4.png)

### Open an app when the notification is clicked:
```bash
terminal-notifier \
    -title 'Address Book Sync' \
    -subtitle 'Finished' \
    -message 'Imported 42 contacts' \
    -activate 'com.apple.AddressBook'
```

![Example 5](assets/Example_5.png)

### Reply
```bash
REPLY=$(terminal-notifier \
    -title 'Reply' \
    -message 'Enter a message' \
    -reply 'Type your message here')
echo "From the user: ${REPLY}"
```

Full output of reply in json:
```bash
terminal-notifier \
    -title 'Reply' \
    -message 'Enter a message' \
    -reply 'Type your message here' \
    -json
```

### Timeout
```bash
terminal-notifier \
    -title 'Timeout' \
    -message 'Reply with a message before it is too late' \
    -reply \
    -timeout 5 \
    -json
```


### Testing Interactive Features

To verify that the repaired callback functionality works correctly:

**Test command execution:**
```bash
terminal-notifier \
    -title 'Test Execute' \
    -message 'Click to run date command' \
    -execute 'date >> /tmp/notification-test.log'
```

**Test application activation:**
```bash
terminal-notifier \
    -title 'Test Activate' \
    -message 'Click to open Terminal' \
    -activate 'com.apple.Terminal'
```

**Test URL opening:**
```bash
terminal-notifier \
    -title 'Test URL' \
    -message 'Click to open GitHub' \
    -open 'https://github.com'
```

After clicking each notification, verify that:
- Commands execute and create log files
- Applications launch as expected
- URLs open in your default browser


## Options

At a minimum, you must specify either the `-message` , the `-remove`, or the `-list` option.

| Option | Type | Default | Description |
|---|---|---|---|
| `-message` | String | None | Message body of the notification, can also be passed via stdin |
| `-list` | String | None | List notifications from the (group) ID, or "ALL" |
| `-remove` | String | None | Remove notifications from the specificed (group) ID, or "ALL" |

### Alert customization options

| Option | Type | Default | Description |
|---|---|---|---|
| `-title` | String | "Terminal" | Title of the notification |
| `-subtitle` | String | None | Subtitle of the notification |
| `-sound` | String | None | Sound to plan, can be found in `/System/Library/Sounds/`, or `default`  |
| `-dropdownLabel` | String | None | Set the label of the dropdown if multiple actions are provided |
| `-closeLabel` | String | None | Set the label of the "Close" button |
| `-contentImage` | String | None | Specify an file ULR to an image to attach inside of the notification |

### Alert response/actions options

| Option | Type | Default | Description |
|---|---|---|---|
| `-actions` | String | None | Comma delimited options for the notification. More then one option displays as a dropdown |
| `-reply` | Optional String | None | Display a reply notification, optional value as the reply placeholder |
| `-wait` | None | None | Wait for the user to click or close the alert |
| `-activate` | String | None | Activate the app (specified by Bundle ID) when the Alert is confirmed |
| `-open` | URL | None | Open the URL when the Alert is confirmed. Can be a web, file or custom schema URL |
| `-execute` | String | None | Execute the shell command when the Alert is confirmed |
| `-json` | None | N/A | Output the response in json |

`reply` and `actions` are exclusive
`reply` and `dropdownLabel` are exclusive

### Alert misc options

| Option | Type | Default | Description |
|---|---|---|---|
| `-group` | String | None | See below |
| `-sender` | String | None | Fake the sender application, see below for details |
| `-timeout` | Number | None | Seconds to wait before exit/removing notification |
| `-ignoreDnD` | None | N/A | Ignore Do Not Distrub settings |

#### Reply

Possible return values:
| Action | "activationType" | "activationValue" |
|---|---|---|
| Close icon | closed | dismissed |
| Click alert | closed | defaultAction |
| Select action choice | actionClicked | <value> |
| Timeout | timeout | <none> |
| Click close label | closed | <value> |

#### Group ID

Specifies the notification’s ‘group’. For any ‘group’, only _one_
notification will ever be shown, replacing previously posted notifications.

A notification can be explicitly removed with the `-remove` option (see
below).

Example group IDs:

* The sender’s name (to scope the notifications by tool).
* The sender’s process ID (to scope the notifications by a unique process).
* The current working directory (to scope notifications by project).

#### Bundle ID

You can find the bundle identifier (`CFBundleIdentifier`) of an application in its `Info.plist` file
_inside_ the application bundle.

Examples application IDs are:

* `com.apple.Terminal` to activate Terminal.app
* `com.apple.Safari` to activate Safari.app

#### Sender ID

Fakes the sender application of the notification. This uses the specified
application’s icon, and will launch it when the notification is clicked.

Using this option fakes the sender application, so that the notification system
will launch that application when the notification is clicked. Because of this
it is important to note that you cannot combine this with options like
`-execute` and `-activate` which depend on the sender of the notification to be
‘terminal-notifier’ to perform its work.

For information on the `ID`, see the `-activate` option.

#### contentImage

The parameter must be a file URL (ie file://....) and should consist of one of the following supported file types:
* https://developer.apple.com/documentation/usernotifications/unnotificationattachment?language=objc#Supported-File-Types


### Example actions usage with a Shell script and [jq](https://github.com/stedolan/jq)

```shell
ANSWER="$(terminal-notifier -message 'Start now ?' -closeLabel No -actions YES,MAYBE,'one more action' -timeout 10 -json | jq .activationType,.activationValue)"

stringarray=($ANSWER)
type=${stringarray[0]}
value=${stringarray[1]}

case $type in
    \"timeout\") echo "Timeout man, sorry" ;;
    \"closed\") echo "You clicked on the default alert' close button" ;;
    \"contentsClicked\") echo "You clicked the alert's content !" ;;
    **) case $value in
            \"YES\") echo "Action YES" ;;
            \"MAYBE\") echo "Action MAYBE" ;;
            **) echo "None of the above" ;;
        esac;;
esac
```

## Development Notes


### Formatting Code

Generate the default config file using Xcode's clang-format version:
```bash
/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-format -style=llvm -dump-config src/main.m > .clang-format
```


## Support & Contributors

### Code Contributors

This project is based on a fork of [terminal notifier](https://github.com/julienXX/terminal-notifier) by [@JulienXX](https://github.com/julienXX)
and code from [alerter](https://github.com/vjeantet/alerter) by [@vjeantet](https://github.com/vjeantet)

## License

All the works are available under the MIT license. **Except** for
‘Terminal.icns’, which is a copy of Apple’s Terminal.app icon and as such is
copyright of Apple.

Copyright (C) 2012-2017 Eloy Durán <eloy.de.enige@gmail.com>, Julien Blanchard
<julien@sideburns.eu>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
