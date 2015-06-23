#!/usr/bin/runhaskell
{-# LANGUAGE OverloadedStrings, ExtendedDefaultRules #-}
{-# OPTIONS_GHC -fno-warn-type-defaults #-}
-- | Checks google calendar and modifies it's printed event in order to
-- color code the upcoming event as a XMobar compatible reminder.
--
-- Prerequisites:
--
--  * https://github.com/insanum/gcalcli installed and in your
--  $PATH
--
-- Motivation:
--
--  * default output has too much information (e.g. date) and takes up
--  to much space in XMobar
--  * I always need to compare if the time is near the current event,
--  which is "hard"
--
-- Program execution:
--
--  * Execute gcalcli with default parameters
--  * parse the output
--  * pick the first, most recent event in the future
--      * if there are no events bail out
--  * parse the string into a data type
--  * check if the upcoming event is in the reminder window
--      * when true, color code the event red
--      * otherwise print the event with time and escription
--
import System.Process (readProcess)
import Data.Time.Format (parseTime, formatTime)
import Data.Time.Clock (NominalDiffTime, UTCTime(..), diffUTCTime, secondsToDiffTime)
import Data.Time (getCurrentTime)
import Data.Time.Calendar (Day(..))
import Data.Time.LocalTime (LocalTime, TimeZone, localTimeToUTC, getCurrentTimeZone, utcToLocalTime)
import System.Locale (defaultTimeLocale)


-- | Google Calendar Event
--
data GCalEvent = GCalEvent UTCTime String

gcalccliCMD :: FilePath
gcalccliCMD = "gcalcli"

gcalcliParams :: UTCTime -> [String]
gcalcliParams now = [ "--nocolor"
                    , "--nostarted"
                    , "--military"
                    , "--calendar=rjoost@redhat.com"
                    , "agenda"
                    , fromDateTime
                    , toDateTime
                    ]
                        where
                            fromDateTime = formatTime defaultTimeLocale "%F %T" now
                            toDateTime = formatTime defaultTimeLocale "%F 22:00:00" now

thisYear :: UTCTime -> String
thisYear = formatTime defaultTimeLocale "%Y"

-- | Interval when we want to be reminded. Defaults to 5min
--
-- TODO: Is there a better way to define this instead of a calculation?
--
-- >>> remindInterval
-- 300s
--
remindInterval :: NominalDiffTime
remindInterval = diffUTCTime (UTCTime day (time + 300)) (UTCTime day 0)
    where day = ModifiedJulianDay 0
          time = secondsToDiffTime 0

-- | eventIsClose
-- Returns True if the event is about to begin
--
-- >>> let now = UTCTime (ModifiedJulianDay 0) (secondsToDiffTime 0)
-- >>> let evTime = UTCTime (ModifiedJulianDay 0) (secondsToDiffTime 200)
-- >>> eventIsClose now (GCalEvent evTime "foo")
-- True
-- >>> let later = UTCTime (ModifiedJulianDay 0) (secondsToDiffTime 500)
-- >>> eventIsClose now (GCalEvent later "foo")
-- False
--
eventIsClose :: UTCTime -> GCalEvent -> Bool
eventIsClose now (GCalEvent evTime _ ) = diffUTCTime evTime now <= remindInterval

-- | Format the event with a XMobar color code if the event is about to
-- start.
--
-- Note: Since GCalEvent keeps the start time of the event in UTC, we'll
-- need to convert it back to local time in order to make sense of it as
-- a human.
--
-- >>> let now = UTCTime (ModifiedJulianDay 0) (secondsToDiffTime 0)
-- >>> let evTime = UTCTime (ModifiedJulianDay 0) (secondsToDiffTime 20)
-- >>> formatNewEvent now (GCalEvent evTime "do something")
-- "<fc=#FF0000>00:00 do something</fc>"
-- >>> let later = UTCTime (ModifiedJulianDay 0) (secondsToDiffTime 500)
-- >>> formatNewEvent now (GCalEvent later "foo")
-- "00:08 foo"
--
formatNewEvent :: TimeZone -> UTCTime -> GCalEvent -> String
formatNewEvent tz now gEvent@(GCalEvent t desc) =
    concat
    (if eventIsClose now gEvent then
    ["<fc=#FF0000>", formattedLocalTime, " ", desc, "</fc>"] else
    [formattedLocalTime, " ", desc])
        where formattedLocalTime = formatTime defaultTimeLocale "%R" $ utcToLocalTime tz t

-- | The year is missing in the output. This function just prepends the
-- current year to the given output.
--
fixDateInOutput :: UTCTime -> String -> String
fixDateInOutput now xs = thisYear now ++ xs

-- | executes gcalcli and reads output
getCLIOutput :: UTCTime -> IO String
getCLIOutput now = readProcess gcalccliCMD (gcalcliParams now) []

-- | remove trailing whitespace, pick the first event which should be
-- the next event and add the year.
--
-- IMPORTANT: Since gcalcli event does not add the year, we can't figure
-- out if the event is about to start. The parser will return a date
-- somewhere in the 70s which is not going to help us.
--
getFirstEventFromOutput :: UTCTime -> String -> String
getFirstEventFromOutput now xs =
    if null (cleanupOutput xs)
    then ""
    else fixDateInOutput now $ head $ cleanupOutput xs

cleanupOutput :: String -> [String]
cleanupOutput outp = filter (not . null) (lines outp)

-- | Turn the first event string into a GCalEvent
--
-- Note: The events time returned by gcalcli is in localtime. We convert
-- it using our Timezone to UTC.
--
-- >>> import Data.Time.LocalTime (utc)
-- >>> let xs = "2015Mon Jun 22 11:45 rpmdiff daily scrum"
-- >>> parseCLIOutput utc xs
-- Just 11:45 rpmdiff daily scrum
-- >>> parseCLIOutput utc "No meetings"
-- Nothing
-- >>> parseCLIOutput utc "No Events Found ..."
-- Nothing
--
parseCLIOutput :: TimeZone -> String -> Maybe GCalEvent
parseCLIOutput tz xs = do
    time <- stringToTime (fst timeAndDesc)
    return $ GCalEvent (localTimeToUTC tz time) (snd timeAndDesc)
    where stringToTime :: String -> Maybe LocalTime
          stringToTime = parseTime defaultTimeLocale "%Y%a %b %d %R"

          timeAndDesc = splitEventDescFromTime xs

-- | splitEventDescFromTime
-- The output we get is a combination of a formated date/time and the
-- event. In order to parse the date/time part we extract the part with
-- the date/time information
--
-- >>> splitEventDescFromTime "Mon Jun 22 11:45 rpmdiff daily scrum"
-- ("Mon Jun 22 11:45","rpmdiff daily scrum")
-- >>> splitEventDescFromTime "Foo bar"
-- ("Foo bar","")
--
splitEventDescFromTime :: String -> (String, String)
splitEventDescFromTime xs = (unwords $ fst tuple, unwords $ snd tuple)
    where tuple = splitAt 4 $ words xs

main :: IO ()
main = do
    now <- getCurrentTime
    tz <- getCurrentTimeZone
    outp <- getCLIOutput now
    case parseCLIOutput tz (getFirstEventFromOutput now outp) of
        Just gcalEvent -> putStrLn $ formatNewEvent tz now gcalEvent
        Nothing -> putStrLn "--"