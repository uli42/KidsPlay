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
them...

Here's what I changed: KidsPLay now supports multiple macros per
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
