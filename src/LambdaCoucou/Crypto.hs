{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module LambdaCoucou.Crypto (fetchCrypto, CryptoCoin(..)) where

import Data.Scientific
import Data.Monoid
import Data.Text (Text, pack)
import qualified Network.IRC.Client as IRC
import Network.HTTP.Req
import Control.Monad.IO.Class
import qualified Data.ByteString as B

import Control.Exception
import qualified Network.HTTP.Client as H
import qualified Network.HTTP.Types as HT

import Control.Lens
import Data.Aeson.Lens

import qualified LambdaCoucou.Types as T

data CryptoCoin = Ethereum | Bitcoin deriving (Show, Eq)

fetchCrypto :: CryptoCoin -> IRC.StatefulIRC T.BotState (Maybe Text)
fetchCrypto coin = do
    let target = "eur"
    r <- liftIO $ catch (fetch coin target) (handleHttp coin)
    pure $ Just r

fetch :: CryptoCoin -> Text -> IO Text
fetch coin target = do
    resp <- liftIO (getCrypto coin target)
    case parseResponse (responseBody resp) of
        Nothing -> do
            putStrLn "Cannot parse response from cryto api"
            pure "Something wrong happened. Error has been logged"
        Just p ->
            pure
                $  "1 "
                <> symbol coin
                <> " vaut "
                <> pack (show p)
                <> " "
                <> target
                <> " grâce au pouvoir de la spéculation !"


getCrypto :: (MonadIO m) => CryptoCoin -> Text -> m BsResponse
getCrypto coin target = do
    let pair = symbol coin <> target
    liftIO $ T.runHttp $ req
        GET
        (https "api.cryptowat.ch" /: "markets" /: exchange coin /: pair /: "price")
        NoReqBody
        bsResponse
        mempty

parseResponse :: B.ByteString -> Maybe Scientific
parseResponse raw = raw ^? key "result" . key "price" . _Number

handleHttp :: CryptoCoin -> HttpException -> IO Text
handleHttp coin (VanillaHttpException (H.HttpExceptionRequest _req (H.StatusCodeException resp _msg)))
    | s == HT.status400
    = pure $ "Currency not found: " <> symbol coin
    | HT.statusCode s == 429
    = pure "Rate limit exceeded"
    | otherwise
    = error "wip"
    where s = H.responseStatus resp

handleHttp coin e = do
    liftIO $ putStrLn $ "Error for " <> show coin <> " : " <> show e
    pure "Something wrong happened. Error has been logged"


-- TODO there may be a better way to do that
exchange :: CryptoCoin -> Text
exchange Bitcoin = "bitstamp"
exchange Ethereum = "bitstamp"

symbol :: CryptoCoin -> Text
symbol Bitcoin = "btc"
symbol Ethereum = "eth"
