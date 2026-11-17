# SpreadJam Timer
*Count up or down cumulative game jam footage - especially for SpreadJams.*

The **SpreadJam Timer** is a tool for assisting in conducting a SpreadJam game jam or tracking production of a prototype.

**This tool can be used to:**
 - Take part in [SpreadJam](./SpreadJam.md) game jams
 - Time the production of 6, 8 or 12 hour prototypes
 - Count accumulated OBS footage

The tool calculates the total duration of OBS ouput, and adds the current recording time (giving you a running total of recorded footage) and displays it in the corner of your OBS footage.

## What is SpeadJam?

**SpreadJam** comes as a ruleset for a game making challenge and this utility for OBS that, when combined, allow for a game making challenge to be spread-out over multiple sittings. [For information on conducting SpreadJam game jams check out this doc within this repository.](./SpreadJam.md)


## Getting Started

Spreadjams require the software in this repository and OBS. All tools should be available for most Operating Systems.

1. Download and install [OBS](https://obsproject.com/download) screen recorder.

2. Download [this tool](https://github.com/daleblackwood/spreadjam/archive/refs/heads/main.zip) and extract it somewhere memorable.

3. Open OBS, and open `File > Settings` from the header menu, go down to `Output`. Set the `Recording Path` field to the folder you wish to place your recordings in (both `Simple` and `Advanced` output modes work). Click `OK` to submit.

4. From the header menu, open `Tools > Scripts`, click the plus `+` button and locate the `SpreadJam.lua` from the folder you extracted it to earlier. The same script works on Windows, macOS and Linux.

5. You're ready to go. Every video you add to the folder you specified under `Recording Path` will count towards your total jam time.

6. Happy jamming. Have fun. Show me what you made.


## The timer text source

With `Automatically Add` ticked, SpreadJam creates a text source named `SpreadJam` (GDI+ on Windows, FreeType 2 on macOS/Linux) and adds it to the current scene, styled and positioned using the script's `Display Size` and `Position` settings.

If you'd rather style it yourself, create your own text source named `SpreadJam` (either `Text (GDI+)` or `Text (FreeType 2)`). SpreadJam will only update its text and leave your font, colour and position alone.

## Troubleshooting

### I see *SJ24  Error: Please set recording output path.* instead of a timer.

You haven't set a recording path yet. It's important to set it this way so SpreadJam knows where to look for your video length calculations. Follow step 3 under Getting Started again.

### It doesn't seem to be calculating the time of my videos correctly.

Make sure you've got the recording path set correctly, following step 3 in Getting Started. If you believe you have and there's an error, file a bug report on [The SpreadJam Github](https://github.com/daleblackwood/spreadjam)
