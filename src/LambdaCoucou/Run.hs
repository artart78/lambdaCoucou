{-# LANGUAGE OverloadedStrings #-}

module LambdaCoucou.Run where

import System.Random (getStdGen)
import qualified Control.Concurrent.STM.TVar as STM
import qualified Control.Concurrent.STM.TBQueue as STM
import Control.Concurrent.Async (withAsync)
import Data.Monoid ((<>))
import Control.Monad.IO.Class (liftIO)
import Data.ByteString (ByteString)
import Data.Text (Text)
import qualified Text.Megaparsec.Error as Error

import qualified Network.IRC.Client as IRC

import qualified LambdaCoucou.Types as T
import qualified LambdaCoucou.Parser as Parser
import qualified LambdaCoucou.Command as Cmd
import LambdaCoucou.Social (updateLastSeen)
import LambdaCoucou.Db (readSocial, readFactoids, updateDb)

run :: ByteString -> Int -> Text -> IO ()
run host port nick = do
    let logger = IRC.stdoutLogger
    conn <- IRC.connectWithTLS' logger host port 1
    let cfg = IRC.defaultIRCConf nick
    let commandHandler =
            IRC.EventHandler "command handler" IRC.EPrivmsg commandHandlerFunc
    let cfg' =
            cfg
            { IRC._eventHandlers = commandHandler : IRC._eventHandlers cfg
            , IRC._channels = ["#gougoutest"]
            , IRC._ctcpVer = "λcoucou, a haskell bot in beta"
            }
    state <- initialState
    let writerQueue = T._writerQueue state
    withAsync (updateDb writerQueue) $
        \_ -> IRC.startStateful conn cfg' state


commandHandlerFunc :: IRC.UnicodeEvent -> IRC.StatefulIRC T.BotState ()
commandHandlerFunc ev = do
    let (IRC.Privmsg _ eitherMessage) = IRC._message ev
    case eitherMessage of
        Left _ -> return () -- CTCP
        Right raw -> do
            updateLastSeen (IRC._source ev)
            case Parser.parseCommand raw of
                Left err ->
                    liftIO . print $ "parse error: " <> Error.parseErrorPretty err
                Right cmd -> do
                    liftIO $ print $ "got command: " <> show cmd
                    Cmd.handleCommand ev cmd


initialState :: IO T.BotState
initialState = do
    eitherFactoids <- readFactoids
    eitherSocial <- readSocial
    case (eitherFactoids, eitherSocial) of
        (Left parseError, _) -> error $ "Error reading factoids: " <> parseError
        (_, Left parseError) -> error $ "Error reading social db: " <> parseError
        (Right factoids, Right socialDb) -> do
            facts <- STM.newTVarIO factoids
            social <- STM.newTVarIO socialDb
            stdGen <- getStdGen >>= STM.newTVarIO
            writerQueue <- STM.newTBQueueIO 10
            return
                T.BotState
                { T._stdGen = stdGen
                , T._factoids = facts
                , T._socialDb = social
                , T._writerQueue = writerQueue
                }
