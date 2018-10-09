This repo contains all released versions (see the tags) of Peter
Watkins' (peterw@tux.org) KidsPlay plugin for
SqueezeBoxServer/SqueezeCenter/LogitechMediaCenter. Unfortunately the
original download site is down now so I set up this git repo. The last
released version was 2.6.2.

Peter describes the plugin likes this:
<i>Have SqueezeCenter execute specific sets of commands for certain
buttons, so you can give a child a remote control with limited
function, or redefine Boom or Radio 1-6 preset buttons or the button
on a Squeezebox Receiver. (Boom, Classic, Radio, Receiver, Slimp3,
Squeezebox1, Transporter)</i>

The latest commits contain some enhancements by me.
Some years ago I had extended version 2.6.2 and sent it to Peter. He
liked it but suggested some changes before releasing it. I never came
around implementing those changes and then eventually forgot about
them... And now he seem not be reachable anymore ;-(

Here's what I changed: KidsPlay now supports multiple macros per
button that are cycled in a round-robin fashion on every press of the
button. This way one can e.g. put several albums of one artist on one
preset button and cycle trough them easily.

Configuration is simple: Add further macros to a button by separating
them with "---" in a line of its own, e.g.

```
kidsplayvolume 50;
---
kidsplayvolume 40;
---
kidsplayvolume 30;
```

This will set the volume to 50 on the first press, to 40 on the second
and to 30 on the third press. Pressing once again will set it to 50
again.


# Excerpts from online documentation

Macros are sets of CLI commands separated by semicolons. For a full
list of "core" SqueezeCenter CLI commands, see the online
documentation. Note: you do not need to include the playerid for
commands that begin with a playerid. For instance, the documentation
says to turn a specific player on you would use `'04:20:00:12:23:45
power 1'` but for KidsPlay you need only use `'power 1'`. If you want to
specify a particular player, insert either the player MAC/ID plus a
colon or the name you assigned to the player plus a colon before the
command, e.g. `'04:20:00:67:89:9a: power 1'` or `'Kitchen: power 1'`. If
you want to have the same command run on every player, insert `'ALL:'`
before the command, e.g. `'ALL: power 1'`. To have the command run on
all players except the player where you pressed the button, insert
`'OTHERS:'`, e.g. `'OTHERS: power 1'`.

## Special characters and variables
There are seven characters that must be escaped with a backslash in your macros:
* `\` (backslash)
* `;` (semicolon)
* `"` (double quotation mark)
* `[` `]` (open and close square brackets)
* `{` `}` (open and close curly braces) 

For example, if you wanted to display `Hello, "Bob"` on a Squeezebox,
you would use a command like display `"Hello \"Bob\""`

If you use a backslash before any other character, then the two
characters will be treated as separate characters -- this means that
Windows directory paths like `c:\windows can be entered as c:\\windows
or c:\windows`.

KidsPlay also understands a few special variable names. Variables are
enclosed in curly braces and are interpreted in the context of the
Squeezebox where the button was pressed. For instance, `ALL: display
"{CURRENT_TRACK_TITLE} is playing on {PLAYER_NAME}"` would display a
message like `"Veronique is playing on Kitchen Boom"` on all
players. The following variables are supported:

* `PLAYER_NAME`
Name of the player where the button was pressed
* `PLAYER_ID`
ID (MAC address) of the player where the button was pressed
* `CURRENT_TRACK_ALBUM`
Album for the current track on the player where the button was pressed
* `CURRENT_TRACK_ARTIST`
Artist for the current track on the player where the button was pressed
* `CURRENT_TRACK_TITLE`
Song title for the current track on the player where the button was pressed
* `CURRENT_TRACK_ID`
Database ID number for the current track on the player where the button was pressed

## Sample macros
* Play a specific regular playlist
`power 1; stop; playlist clear; mixer volume 30; playlist play "Playlist Name";`
* Play a specific iTunes playlist (note that " " becomes "%20", as the `itunesplaylist:` argument should itself look like a URL)
`power 1; stop; playlist clear; mixer volume 30; playlist play "itunesplaylist:Playlist%20Name";`
* Random mix from one genre
`power 1; stop; playlist clear; mixer volume 30; randomplaygenreselectall 0; randomplaychoosegenre GenreName 1; randomplay tracks;`
* Play a specific album
`power 1; stop; playlist clear; mixer volume 30; playlist play "/path/to/album/directory"`
* Display a message
`show "line1:KidsPlay test" "line2:Your message here" duration:5 centered:1`
* Display a large message
`show font:huge "line2:Your message here" duration:5 centered:1`
* Set volume to a fixed level
`mixer volume 45;`
or 
`kidsplayvolume 45`
* Increase volume by 5, but not greater than player's KidsPlay max
`kidsplayvolume +5`
* Decrease volume by 5, but not less than player's KidsPlay min
`kidsplayvolume -5`
* Set volume to player's KidsPlay minimum
`kidsplayvolume 0`
* Toggle between two values (3 = Always Off, 0 = Headphones) for a Boom's analogOutMode pref (this command currently only supports switching between two values)
`kidsplaytoggleclientpref analogOutMode 3 0`
* Turn the player named "Living Room" off (note the space and quotation marks)
`"Living Room:" power 0`
* Turn all players off
`ALL: power 0`
* Turn all other players off but leave this one alone
`OTHERS: power 0`

## KidsPlay CLI commands
* `00:04:20:11:22:33 kidsplayvolume ARG`
increase (if ARG begins with "+"), decrease (if ARG begins with "-"), or set the exact volume level (0-100) for the specified player, but do only within the bounds of the KidsPlay minimum and KidsPlay maximum volumes for that player
* `00:04:20:11:22:33 kidsplaytoggleclientpref PREFNAME VALUE1 VALUE2`
Toggle between VALUE1 and VALUE2 for preference PREFNAME for the specified player
* `kidsplayexec SECRET COMMAND (additional arguments optional)`
Execute the specified command on the system where Squeezebox Server is running. You may pass mutiple arguments if needed. The SECRET value is different for each Squeezebox Server installation; do not share your SECRET value with anyone else. Note: you MUST enable Password Protection and set the CSRF Protection Level to Medium or High in the security settings in order to use this CLI command. 
* `kidsplayexec status: Enabled Your SECRET value is 14229109`
