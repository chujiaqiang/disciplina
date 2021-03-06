module Test.Dscp.Educator.BlockValidation where

import Test.Common

import Control.Lens (to)
import Dscp.Core (ATGDelta (..), CourseId (..), Grade (..),
                  swKey, swSig, ssSubmission, ssWitness)
import Dscp.Crypto (AbstractPK (..), AbstractSK (..), PublicKey, SecretKey,
                    hash, getMerkleRoot, fromFoldable)
import Dscp.Educator (PrivateBlock (..), PrivateBlockBody (..), PrivateBlockHeader (..),
                      PrivateTx (..), BlockValidationFailure (..), SubmissionValidationFailure (..),
                      genesisHeaderHash, validatePrivateBlk, ptSignedSubmission)

import System.IO.Unsafe (unsafePerformIO)
import qualified Crypto.PubKey.Ed25519 as Ed25519
import qualified Data.Map.Strict as M

courseCompScience1 :: CourseId
courseCompScience1 = CourseId 3

studentAPubKey, studentBPubKey :: PublicKey
studentAPubKey = mkPubKey 'a'
studentBPubKey = mkPubKey 'b'

studentAPrivKey, studentBPrivKey :: SecretKey
studentAPrivKey = mkPrivKey 'a'
studentBPrivKey = mkPrivKey 'b'

studentAKeyPair :: (PublicKey, SecretKey)
studentAKeyPair = mkKeyPair 'a'

-- | Educator 'k' grade student a an B in course Computer science
-- transaction is signed by student a
tx1, tx2, tx3, tx4 :: PrivateTx
tx1 = mkPrivateTx courseCompScience1 B studentAPubKey studentAKeyPair

-- | Educator 'k' grade student a an B in course Computer science
-- transaction is signed by student b
tx2 = mkPrivateTx courseCompScience1 B studentAPubKey (studentAPubKey, studentBPrivKey)

tx3 = mkPrivateTx courseCompScience1 B studentAPubKey (studentBPubKey, studentAPrivKey)

tx4 = mkPrivateTx courseCompScience1 B studentBPubKey (studentBPubKey, studentBPrivKey)

-- | unsafePerformIO create bunch of PrivateTx.
-- Use map instead of replicate here to force
-- unique key pairs
txsValid :: [PrivateTx]
txsValid = map generateKeyPair [1..(100 :: Int)]
  where generateKeyPair _ =
          let key = unsafePerformIO Ed25519.generateSecretKey
              kp@(pubKey, _) = (AbstractPK (Ed25519.toPublic key), AbstractSK key)
          in mkPrivateTx courseCompScience1 B pubKey kp

spec_ValidateBlock :: Spec
spec_ValidateBlock = describe "Validate private block" $ do
    it "can validate valid block" $ do
        validatePrivateBlk (mkBlock [tx1]) `shouldBe` Right ()
        validatePrivateBlk (mkBlock [tx1, tx4]) `shouldBe` Right ()
        validatePrivateBlk (mkBlock txsValid) `shouldBe` Right ()
    it "do not validate non-valid transaction signatures " $ do
        validatePrivateBlk (mkBlock [tx2]) `shouldBe`
          Left [SubmissionInvalid
                 (SubmissionSignatureMismatch { svfSubmissionHash = hashTxSub tx2
                                              , svfSubmissionSig = getTxSig tx2
                                              , svfSubmissionSigKey = getTxKey tx2
                                              })]
        validatePrivateBlk (mkBlock [tx3]) `shouldBe`
          Left [SubmissionInvalid
                 (SubmissionPublicKeyMismatch { svfExpectedPubKey = hash studentAPubKey
                                              , svfActualPubKey = hash (getTxKey tx3)
                                              })
               ,SubmissionInvalid
                 (SubmissionSignatureMismatch { svfSubmissionHash = hashTxSub tx3
                                              , svfSubmissionSig = getTxSig tx3
                                              , svfSubmissionSigKey = getTxKey tx3
                                              })]
    it "do not validate non-valid merkle root " $ do
        let block = mkBlock txsValid
        validatePrivateBlk (replaceMerkleRoot block [tx1, tx2, tx4]) `shouldBe`
          Left [MerkleSignatureMismatch { bvfExpectedSig = mkBodyProof [tx1, tx2, tx4]
                                        , bvfActualMerkleSig = _pbhBodyProof (_pbHeader block)
                                        }]
  where
    getTxKey tx = tx^.ptSignedSubmission.ssWitness.swKey
    getTxSig tx = tx^.ptSignedSubmission.ssWitness.swSig
    hashTxSub tx = tx^.ptSignedSubmission.ssSubmission.to hash
    mkBlock txs = PrivateBlock
        { _pbHeader = mkBlockHeader txs
        , _pbBody = mkBlockBody txs
        }
    mkBlockHeader txs = PrivateBlockHeader
        { _pbhPrevBlock = genesisHeaderHash
        , _pbhBodyProof = mkBodyProof txs
        , _pbhAtgDelta = mkATGDelta
        }
    mkBlockBody txs = PrivateBlockBody
        { _pbbTxs = txs }
    mkBodyProof txs = getMerkleRoot (fromFoldable txs)
    mkATGDelta = ATGDelta M.empty
    replaceMerkleRoot :: PrivateBlock -> [PrivateTx] -> PrivateBlock
    replaceMerkleRoot block txs =
        block { _pbHeader = (_pbHeader block) { _pbhBodyProof = mkBodyProof txs } }
