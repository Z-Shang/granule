-- Defines the 'Checker' monad used in the type checker
-- and various interfaces for working within this monad

{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}

module Checker.Environment where

import Control.Monad.State.Strict

import Control.Monad.Trans.Maybe
import qualified Control.Monad.Trans.Reader as MR
import Control.Monad.Reader.Class

import Checker.Constraints (Constraint)
import Context
import Syntax.Expr (Id, CKind, Span)

-- State of the check/synth functions
newtype Checker a =
  Checker { unwrap :: MR.ReaderT [(Id, Id)] (StateT CheckerState IO) a }

evalChecker :: CheckerState -> [(Id, Id)] -> Checker a -> IO a
evalChecker initialState nameMap =
  flip evalStateT initialState . flip MR.runReaderT nameMap . unwrap

-- For fresh name generation
type VarCounter  = Int

data CheckerState = CS
            { -- Fresh variable id
              uniqueVarId  :: VarCounter
            -- Conjunction of constraints
            , predicate    :: [Constraint]
            -- Coeffect environment, map coeffect vars to their kinds
            , ckenv        :: Env CKind
            -- Environment of resoled coeffect type variables
            -- (used just before solver, to resolve any type
            -- variables that appear in constraints)
            , cVarEnv   :: Env CKind
            }
  deriving Show -- for debugging

initState :: CheckerState
initState = CS 0 ground emptyEnv emptyEnv
  where
    ground   = []
    emptyEnv = []

-- | A helper for adding a constraint to the environment
addConstraint :: Constraint -> MaybeT Checker ()
addConstraint p = do
  checkerState <- get
  put $ checkerState { predicate = p : predicate checkerState }

-- | Stops the checker
halt :: MaybeT Checker a
halt = MaybeT (return Nothing)

-- | A helper for raising a type error
illTyped :: Span -> String -> MaybeT Checker a
illTyped = visibleError "type" halt

illLinearity :: Span -> String -> MaybeT Checker a
illLinearity = visibleError "linearity" halt

illGraded :: Span -> String -> MaybeT Checker ()
illGraded = visibleError "grading" (return ())

-- | Helper for constructing error handlers
visibleError :: String -> (MaybeT Checker a) -> Span -> String -> MaybeT Checker a
visibleError kind next ((0, 0), (0, 0)) s =
  liftIO (putStrLn $ kind ++ " error: " ++ s) >> next

visibleError kind next ((sl, sc), (_, _)) s =
  liftIO (putStrLn $ show sl ++ ":" ++ show sc ++ ": " ++ kind ++ " error:\n\t"
                   ++ s) >> next


-- Various interfaces for the checker

instance Monad Checker where
  return = Checker . return
  (Checker x) >>= f = Checker (x >>= (unwrap . f))

instance Functor Checker where
  fmap f (Checker x) = Checker (fmap f x)

instance Applicative Checker where
  pure    = return
  f <*> x = f >>= \f' -> x >>= \x' -> return (f' x')

instance MonadState CheckerState Checker where
  get = Checker get
  put s = Checker (put s)

instance MonadIO Checker where
  liftIO = Checker . lift . lift

instance MonadReader [(Id, Id)] Checker where
  ask = Checker MR.ask
  local r (Checker x) = Checker (MR.local r x)
