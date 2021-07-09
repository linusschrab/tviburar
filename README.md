# Tviburar

A dual lane four step polyrythmic sequencer where each step contains a free running LFO that will generate notes. The LFO modes are, square, random, ramp up, ramp down and sine. Each step can also be muted. The two sequencers can influence each others LFO values creating a complex environment where the rate of repetition is stretched out over a long, near infinite, timespace. 

Written by Linus Schrab (vicimity) and Filip Forsström (ljudvagg).
The script is based on an original concept built by Filip for the Nord Modular G2.

## How
Tviburar boots up in a calm state with four square wave LFOs outputting notes to the synth engine Polysub. The LFOs are seeded random rates between 0.33 and 0.66hz. Only the top lane (twin 1) is active, twin 2 is muted. Choose your preferred destination in Parameters > Edit > midi & outputs. The destination options are

 - mute
 - polysub
 - midi (with selectable device and channels)
 - crow
 - w/syn
 - jf
 - osc (via the companion m4l-device)

Return to the scripts main screen and scroll through the sequencer steps with E1. E2 takes you through the avaiable LFO settings and E3 changes the selected value. The currently selected LFO is shown with a line above or below the selected step.
To edit the second lane (twin 2) hold down the alt key, K2 and scroll with E1. The currently active lane is shown with a line to the left of the sequencer lane. As with the LFOs, the lanes have settings that are accessible in the same manner as the LFOs. E2 scrolls through the avalable settings and E3 changes its value.
The third setting for lanes "twinfluence" is secret sauce. It amplifies the influence between the two sequencers LFOs, creating complex waveforms for the ramp and sine LFOs and altering the note value, offset and amp for square and random. 

The double nature of Tviburar can be used to sequence two destinations, internal modulation or both at the same time.

## Installation
Enter `;install https://github.com/linusschrab/tviburar` in Matron or via Maidens script library.
