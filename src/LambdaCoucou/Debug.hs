{-# LANGUAGE OverloadedStrings #-}

module LambdaCoucou.Debug where

import           Control.Monad
import qualified Control.Monad.State.Strict as St
import qualified Data.Text                  as Tx
import qualified LambdaCoucou.State         as LC.St
import qualified Network.IRC.Client         as IRC.C
import qualified Network.IRC.Client.Events  as IRC.Ev

debugEventHandler :: IRC.Ev.EventHandler LC.St.CoucouState
debugEventHandler = IRC.Ev.EventHandler
  (IRC.Ev.matchType IRC.Ev._Privmsg)
  (\source (_target, raw) -> case (source, raw) of
    (IRC.Ev.User nick, Right msg) -> when (nick == "Geekingfrog") $
      when (msg == "state") $ do
        st <- St.get
        IRC.C.replyTo source (Tx.pack $ show st)

    _ -> pure ()
  )