# SpreadJam
*A jam which spreads the development, not the developer.*

**SpreadJam** comes as a ruleset for a game making challenge and a utility for OBS that, when combined, allow for a game making challenge to be spread-out over multiple sittings.

## What is a SpreadJam?

A SpreadJam is a game jam taken over multiple sittings. Unlike the popular and traditional 48 hour game jams (like the Ludam Dare or the GMTK Jam), SpreadJams are not contigious and allow free time for time away from game production - time for ideation, experimentation, eating, sleeping, a day job - whatever you like.

As a trade off, the total number of hours in a SpreadJam is half that of a traditional challenge, running at 24 just hours. The theory is that a developer with a sound mind, free mind and all the spare time in the world to think, can probably jam a great game too.

In order to do a SpreadJam, grab the tools here and follow the rules below. Anyone can do it at any time.

## Why is a SpreadJam?

Game jams can be a lot of fun but the commitment can be daunting and the endless, sleepless rush can promote crunch, a practice the games industry is already too comfortable with. SpreadJams are a way for busy or conscientious developers to join in on the fun responsibly, at their own pace.

## SpreadJam Rules

### 24 hours - Split 'em how you like 'em
- A SpreadJam game is a game made over several screen-recorded sessions whose total footage does not exceed 24 hours.
- The entireity of the game must be completed within the alotted time.

### What goes on in SpreadJam, stays in SpreadJam
- All assets and code must be produced within the challenge.
    - Game engines are allowed
    - Generalized asset creation or generation tools are allowed (sfxer, Blender, Houdini, etc...) so long as they are not build specifically for your game prior to jam time.
    - Ready-made models / music / art and code are not allowed
- The author(s) can have as much time away from recording and as they wish, and break the challenge into as many segments as they wish so long as no active development is undertaken away from the screen recordings.
- Any design or production artefacts created away from computer must also be recorded as video and added to the total pool, taking from the total duration of the challenge.
    - These videos do not need to display a timer
    - This footage must be unbroken and show all working.

### What goes on elsewhere, stays elsewhere
- Experiments may be conducted, or recorded ideation performed (writing/drawing/coding/practicing) outside of SpreadJam project development so long as:
    - No artefacts from the SpreadJam project are used to conduct the experiments or ideation
    - No artefacts from the experiments or ideation are brought back into the SpreadJam project
    - No experiments or ideation are used as reference during the production of the SpreadJam game

### You can jam with a mate, but it'll cost you
- Any work contributed from other developers must take hours from, and contribute footage to, the same time and footage pool as the project lead. This footage must follow the same rules as off-screen artefacts. (Unbroken, show all working.)


### The Tools enforce the rules
- The whole development of the SpreadJam project must be recorded with a timer visible on screen:
    - The timer must display the total duration of the cumulative footage of the project's development.
    - The timer must be visible in all screen-recorded videos.
- It's best to use this tool and OBS or build one that works in an identical fashion.


## Getting Started

Spreadjams require the software in this repository and OBS. All tools should be available for most Operating Systems.

1. Download and install [OBS](https://obsproject.com/download) screen recorder.

2. Download [this tool](https://github.com/daleblackwood/spreadjam/archive/refs/heads/main.zip) and extract it somewhere memorable.

3. Open OBS, and open `File > Settings` from the header menu, go down to `Output`. Set the `Output Mode` at the top to `Simple` and set the `Recording Path` field to the folder you wish to place your recordings in. Click `OK` to submit.

4. From the header menu, open `Tools > Scripts`, click the plus `+` button and locate the `SpreadJam.lua` from the folder you extracted it to earlier.

5. You're ready to go. Every video you add to the folder you specified under `Recording Path` will count towards your total jam time.

6. Happy jamming. Have fun. Show me what you made.

## Troubleshooting

### I see *SJ24  Error: Please set recording output path.* instead of a timer.

You're either not in Basic Mode or you haven't set the recording path in basic mode yet. It's important to set it this way so SpreadJam knows where to look for your video length calculations. Follow step 3 under Getting Started again.

### It doesn't seem to be calculating the time of my videos correctly.

Make sure you've got the path set correctly in Basic Mode, following step 3 in Getting Started. If you believe you have and there's an error, file a bug report on [The SpreadJam Github](https://github.com/daleblackwood/spreadjam)
