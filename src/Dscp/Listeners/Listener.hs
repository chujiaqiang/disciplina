
-- | Node Listeners

module Dscp.Listeners.Listener where

import Universum

import qualified Data.ByteString as BS
import Loot.Log (logInfo)
import Node (ConversationActions, Listener (..), NodeId, send)

import Dscp.Messages (Packing, PingBlk, PingTx, PongBlk (..), PongTx (..))
import Dscp.Witness.Launcher (WitnessWorkMode)

witnessListeners
    :: forall m. WitnessWorkMode m
    => NodeId -> BS.ByteString -> [Listener Packing BS.ByteString m]
witnessListeners _anId _peerData = [blkListener, txListener]
    where
    blkListener :: Listener Packing BS.ByteString m
    blkListener = Listener $ \_ _peerId (cactions :: ConversationActions PongBlk PingBlk m) -> do
        logInfo "heard Blk"
        send cactions (PongBlk "")
    txListener :: Listener Packing BS.ByteString m
    txListener = Listener $ \_ _peerId (cactions :: ConversationActions PongTx PingTx m) -> do
        logInfo "heard Tx"
        send cactions (PongTx "")