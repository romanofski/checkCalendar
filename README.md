# checkCalendar

Checks google calendar by using gcalcli and modifies it's printed event
in order to color code the upcoming event as a XMobar compatible
reminder.

## Prerequisites

 * https://github.com/insanum/gcalcli installed and in your
 $PATH

## Motivation

 * default output has too much information (e.g. date) and takes up
 to much space in XMobar
 * I always need to compare if the time is near the current event,
 which is "hard"

## Installation

The command `make install` installs it into `$HOME/bin`.

The `checkCalendar` binary passes it's arguments onto `gcalcli`. It
invokes `gcalcli` with the `agenda` keyword and picks the first upcoming
event.

Example:

    Run Com "checkCalendar" ["--nocolor", "--nostarted", "--military", "--calendar=mycalendar"] "gcal" 600
