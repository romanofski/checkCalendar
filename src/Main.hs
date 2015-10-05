#!/usr/bin/runhaskell
{-# LANGUAGE OverloadedStrings, ExtendedDefaultRules #-}
{-# OPTIONS_GHC -fno-warn-type-defaults #-}

module Main where

import System.Process (readProcess)
import Data.Time.Format (parseTime, formatTime)
import Data.Time.Clock (NominalDiffTime, UTCTime(..), diffUTCTime)
import Data.Time (getCurrentTime)
import Data.Time.LocalTime (LocalTime, TimeZone, localTimeToUTC, getCurrentTimeZone, utcToLocalTime)
import System.Locale (defaultTimeLocale)
import System.Environment (getArgs)
import Data.Bifunctor (bimap)

-- $setup
-- >>> import Data.Time.Clock (secondsToDiffTime)
-- >>> import Data.Time.Calendar (Day(..))
-- >>> tz <- getCurrentTimeZone
-- >>> let now = UTCTime (ModifiedJulianDay 0) (secondsToDiffTime 0)
-- >>> let later = UTCTime (ModifiedJulianDay 0) (secondsToDiffTime 500)
-- >>> let evTime = UTCTime (ModifiedJulianDay 0) (secondsToDiffTime 200)


-- | Google Calendar Event
--
data GCalEvent = GCalEvent UTCTime String
    deriving Show

data ParseError = ParseError String
                deriving Show

gcalccliCMD :: FilePath
gcalccliCMD = "gcalcli"

gcalDefaultParams :: LocalTime -> [String]
gcalDefaultParams now =
    [ "--military"
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
remindInterval :: NominalDiffTime
remindInterval = 300

-- | eventIsClose
-- Returns True if the event is about to begin
--
-- >>> eventIsClose now (GCalEvent evTime "foo")
-- True
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
-- >>> putStrLn $ formatNewEvent tz now (GCalEvent evTime "do something")
-- <fc=#FF0000>... do something</fc>
-- >>> putStrLn $ formatNewEvent tz now (GCalEvent later "foo")
-- ... foo
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

-- | Executes gcalcli and reads output
--
getCLIOutput :: FilePath -> [String] -> IO String
getCLIOutput cmd args = readProcess cmd args []

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
-- Note: The events time returned by gcalcli are in localtime. We convert
-- it using our Timezone to UTC.
--
-- >>> import Data.Time.LocalTime (utc)
-- >>> let xs = "2015Mon Jun 22 11:45 rpmdiff daily scrum"
-- >>> parseCLIOutput tz xs
-- Right (GCalEvent 2015-06-22 01:45:00 UTC "rpmdiff daily scrum")
-- >>> parseCLIOutput tz "No meetings"
-- Left (ParseError "Invalid time: No meetings")
--
parseCLIOutput :: TimeZone -> String -> Either ParseError GCalEvent
parseCLIOutput tz xs = do
    time <- parseGcalcTime (fst timeAndDesc)
    return $ GCalEvent (localTimeToUTC tz time) (snd timeAndDesc)
    where timeAndDesc = splitEventDescFromTime xs

parseGcalcTime :: String -> Either ParseError LocalTime
parseGcalcTime str = case parseTime defaultTimeLocale "%Y%a %b %d %R" str of
  Just t -> Right t
  Nothing -> Left (ParseError $ "Invalid time: " ++ str)

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
splitEventDescFromTime xs = bimap unwords unwords tuple
    where tuple = splitAt 4 $ words xs

main :: IO ()
main = do
    args <- getArgs
    now <- getCurrentTime
    tz <- getCurrentTimeZone
    outp <- getCLIOutput gcalccliCMD $ args ++ gcalDefaultParams (utcToLocalTime tz now)
    case parseCLIOutput tz (getFirstEventFromOutput now outp) of
        Right gcalEvent -> putStrLn $ formatNewEvent tz now gcalEvent
        Left (ParseError err) -> putStrLn err
