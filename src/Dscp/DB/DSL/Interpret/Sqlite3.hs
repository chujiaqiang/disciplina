
{-# LANGUAGE QuasiQuotes #-}

module Dscp.DB.DSL.Interpret.Sqlite3 () where

import qualified Data.Set as Set (Set, empty, member, singleton)

import Database.SQLite.Simple (Only (..))

import Text.InterpolatedString.Perl6 (q, qc, qq)

import Dscp.Crypto (PublicKey)
import Dscp.DB.DSL.Class
import Dscp.DB.SQLite
import Dscp.Educator.Txs (PrivateTx (..), PrivateTxId)

instance
--    v-- GHC says it cand "find" Monad in superclasses (wat).
    ( Monad m
    , MonadSQLiteDB m
    )
    => MonadSearchTxObj m
  where
    runTxQuery (SELECTTx WHERE (TxIdEq pid)) =
        getPrivateTxFromId (error "get pk from keyring here") pid

    -- TODO (kir): find where the 'Obj'ects live.
    runObjQuery (SELECTObj WHERE (ObjHashEq _hash)) =
        return Nothing

    runTxsQuery (SELECTTxs WHERE txFilter) =
        getPrivateTxsByFilter (error "get pk from keyring here") txFilter

getPrivateTxsByFilter
    :: MonadSQLiteDB m
    => PublicKey
    -> TxsFilterExpr
    -> m [PrivateTx]
getPrivateTxsByFilter pk filterExpr = do
    let
      tables = requiredTables filterExpr

      -- The [qc||] cannot occur inside its {}-interpolator :(
      -- Expression [qc| {[qc||]} |] gives an error.
      additionalJoins :: Text
      additionalJoins =
        if Subject `Set.member` tables
        then [qc|

            left join Courses     on  Assignment.course_id       = Courses.id
            left join Subjects    on    Subjects.course_id       = Courses.id

             |]
        else [qc||]

    fmap ($ pk) <$> query
        [qc|
            select    Submissions.student_addr,
                      Submissions.contents_hash,

                      Assignments.course_id,
                      Assignments.contents_hash,
                      Assignments.desc,

                      Submissions.signature,

                      Transactions.grade,
                      Transactions.time

            from      Transactions

            left join Submissions on             submission_hash = Submissions.hash
            left join Assignments on Submissions.assignment_hash = Assignments.hash
            {
                additionalJoins
            }
            where {buildWhereStatement filterExpr}
            ;
        |]
        ()

buildWhereStatement :: TxsFilterExpr -> Text
buildWhereStatement = go
  where
    go = \case
        TxHasSubjectId sid   -> [qq| Subjects.id = $sid   |]
        TxGradeEq      grade -> [qq| grade       = $grade |]
        TxGrade :>=    grade -> [qq| grade      >= $grade |]

        left :&  right       -> [qq| ({go left}) and ({go right}) |]
        left :|| right       -> [qq| ({go left}) or  ({go right}) |]

        TxHasDescendantOfSubjectId _sid ->
            error "buildWhereStatement: TxHasDescendantOfSubjectId: not supported yet"

getPrivateTxFromId :: MonadSQLiteDB m => PublicKey -> PrivateTxId -> m (Maybe PrivateTx)
getPrivateTxFromId pk tid = do
    pack <- query
        [q|
            select    Submissions.student_addr,
                      Submissions.contents_hash,

                      Assignments.course_id,
                      Assignments.contents_hash,
                      Assignments.desc,

                      Submissions.signature,

                      Transactions.grade,
                      Transactions.time

            from      Transactions

            left join Submissions on             submission_hash = Submissions.hash
            left join Assignments on Submissions.assignment_hash = Assignments.hash

            where     Transactions.hash = ?;
        |]
        (Only tid)

    return $ case pack of
        [queryResult] -> Just (queryResult pk)
        _other        -> Nothing

data RequiredTables
    = Subject
    deriving (Eq, Ord)

requiredTables :: TxsFilterExpr -> Set.Set RequiredTables
requiredTables = \case
    TxHasSubjectId             _ -> Set.singleton Subject
    TxHasDescendantOfSubjectId _ -> Set.singleton Subject
    (:||) a b                    -> requiredTables a <> requiredTables b
    (:&)  a b                    -> requiredTables a <> requiredTables b
    _other                       -> Set.empty
