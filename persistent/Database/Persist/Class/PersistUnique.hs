{-# LANGUAGE CPP #-}
{-# LANGUAGE TypeFamilies #-}
module Database.Persist.Class.PersistUnique
    ( PersistUnique (..)
    ) where

import qualified Prelude
import Prelude hiding ((++), show)

import Control.Monad (liftM)
import Control.Monad.Trans.Error (Error (..))
import Control.Monad.Trans.Class (lift)
import Data.Monoid (Monoid)

import Data.Conduit.Internal (Pipe)
import Control.Monad.Logger (LoggingT)
import Control.Monad.Trans.Identity ( IdentityT)
import Control.Monad.Trans.List     ( ListT    )
import Control.Monad.Trans.Maybe    ( MaybeT   )
import Control.Monad.Trans.Error    ( ErrorT   )
import Control.Monad.Trans.Reader   ( ReaderT  )
import Control.Monad.Trans.Cont     ( ContT  )
import Control.Monad.Trans.State    ( StateT   )
import Control.Monad.Trans.Writer   ( WriterT  )
import Control.Monad.Trans.RWS      ( RWST     )
import Control.Monad.Trans.Resource ( ResourceT)

import qualified Control.Monad.Trans.RWS.Strict    as Strict ( RWST   )
import qualified Control.Monad.Trans.State.Strict  as Strict ( StateT )
import qualified Control.Monad.Trans.Writer.Strict as Strict ( WriterT )
import Database.Persist.Class.PersistStore
import Database.Persist.Class.PersistEntity

-- | Queries against unique keys (other than the id).
--
-- Please read the general Persistent documentation to learn how to create
-- Unique keys.
-- SQL backends automatically create uniqueness constraints, but for MongoDB you must place a unique index on the field.
class PersistStore m => PersistUnique m where
    -- | Get a record by unique key, if available. Returns also the identifier.
    getBy :: (PersistEntityBackend val ~ PersistMonadBackend m, PersistEntity val) => Unique val -> m (Maybe (Entity val))

    -- | Delete a specific record by unique key. Does nothing if no record
    -- matches.
    deleteBy :: (PersistEntityBackend val ~ PersistMonadBackend m, PersistEntity val) => Unique val -> m ()

    -- | Like 'insert', but returns 'Nothing' when the record
    -- couldn't be inserted because of a uniqueness constraint.
    insertUnique :: (PersistEntityBackend val ~ PersistMonadBackend m, PersistEntity val) => val -> m (Maybe (Key val))
    insertUnique datum = do
        isUnique <- checkUnique datum
        if isUnique then Just `liftM` insert datum else return Nothing

#define DEF(T) { getBy = lift . getBy; deleteBy = lift . deleteBy; insertUnique = lift . insertUnique }
#define GO(T) instance (PersistUnique m) => PersistUnique (T m) where DEF(T)
#define GOX(X, T) instance (X, PersistUnique m) => PersistUnique (T m) where DEF(T)

GO(LoggingT)
GO(IdentityT)
GO(ListT)
GO(MaybeT)
GOX(Error e, ErrorT e)
GO(ReaderT r)
GO(ContT r)
GO(StateT s)
GO(ResourceT)
GO(Pipe l i o u)
GOX(Monoid w, WriterT w)
GOX(Monoid w, RWST r w s)
GOX(Monoid w, Strict.RWST r w s)
GO(Strict.StateT s)
GOX(Monoid w, Strict.WriterT w)

#undef DEF
#undef GO
#undef GOX

-- | Check whether there are any conflicts for unique keys with this entity and
-- existing entities in the database.
--
-- Returns 'True' if the entity would be unique, and could thus safely be
-- 'insert'ed; returns 'False' on a conflict.
checkUnique :: (PersistEntityBackend val ~ PersistMonadBackend m, PersistEntity val, PersistUnique m) => val -> m Bool
checkUnique val =
    go $ persistUniqueKeys val
  where
    go [] = return True
    go (x:xs) = do
        y <- getBy x
        case y of
            Nothing -> go xs
            Just _ -> return False