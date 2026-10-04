#!/usr/bin/env bash
set -euo pipefail

# Register 2560x1440, 3440x1440, and 2560x1600 modes at approximately 60 Hz
# for a Linux Mint VM's Virtual-1 display output in an X11 desktop session.
# Requires xrandr and a display driver that accepts custom modes.
# Run as the desktop user, without sudo: bash ~/scripts/resolution.sh
# This adds choices to Display Settings; it does not switch resolutions.
# To select a mode manually:
#   xrandr --output Virtual-1 --mode "2560x1440_60.00"
# Changes last only for the current X session, not across logout or reboot.
# Re-running may fail if the modes already exist; errors stop the script.
# This script is not intended for Wayland sessions.
#
# Obtain the output name and currently advertised resolutions with:
#   xrandr --query
# Replace Virtual-1 below if your connected output has a different name.
# Generate a modeline for a desired width, height, and refresh rate with:
#   cvt 2560 1440 60
#   cvt 3440 1440 60
#   cvt 2560 1600 60
# cvt calculates VESA Coordinated Video Timings, not the display's supported
# resolutions. Verify that the VM/display driver supports the requested mode.
# Copy everything after "Modeline" from its output into xrandr --newmode:
# the quoted name, pixel clock in MHz, four horizontal timing values, four
# vertical timing values, and horizontal/vertical sync polarity flags.
# The timing values describe active pixels, sync start/end, and total size.
# Use the same quoted name with --addmode to attach it to the output.

xrandr --newmode "2560x1440_60.00" 312.25 2560 2752 3024 3488 1440 1443 1448 1493 -hsync +vsync
xrandr --newmode "3440x1440_60.00" 419.50 3440 3696 4064 4688 1440 1443 1453 1493 -hsync +vsync
xrandr --newmode "2560x1600_60.00" 348.50 2560 2760 3032 3504 1600 1603 1609 1658 -hsync +vsync

xrandr --addmode Virtual-1 "2560x1440_60.00"
xrandr --addmode Virtual-1 "3440x1440_60.00"
xrandr --addmode Virtual-1 "2560x1600_60.00"
