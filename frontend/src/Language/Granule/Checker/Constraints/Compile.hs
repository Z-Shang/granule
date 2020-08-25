{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE ImplicitParams #-}
{-# LANGUAGE FlexibleInstances #-}

module Language.Granule.Checker.Constraints.Compile (compileTypeConstraintToConstraint) where

import Control.Monad.State.Strict

import Language.Granule.Checker.Coeffects
import Language.Granule.Checker.Constraints.CompileNatKinded
import Language.Granule.Checker.Monad
import Language.Granule.Checker.Predicates
import Language.Granule.Checker.SubstitutionAndKinding (checkKind, synthKind)

import Language.Granule.Syntax.Pretty
import Language.Granule.Syntax.Span
import Language.Granule.Syntax.Type

import Language.Granule.Utils

compileTypeConstraintToConstraint ::
    (?globals :: Globals) => Span -> Type -> Checker Pred
compileTypeConstraintToConstraint s (TyInfix op t1 t2) = do
  st <- get
  (k, _) <- synthKind s (tyVarContext st) t1
  (result, putChecker) <- peekChecker (checkKind s (tyVarContext st) t2 k)
  case result of
    Right _ -> do
      putChecker
      case demoteKindToType k of
        Just coeffTy -> compileAtType s op t1 t2 coeffTy
        _ ->  error $ pretty s <> ": I don't know how to compile at kind " <> pretty k
    Left _ ->
      case k of
        KVar v -> do
          st <- get
          case lookup v (tyVarContext st) of
            Just (_, ForallQ) | isGenericCoeffectExpression t2 -> compileAtType s op t1 t2 (TyVar v)
            _ -> throw $ UnificationError s t1 t2
        _ -> throw $ UnificationError s t1 t2
compileTypeConstraintToConstraint s t =
  error $ pretty s <> ": I don't know how to compile a constraint `" <> pretty t <> "`"

compileAtType :: (?globals :: Globals) => Span -> TypeOperator -> Type -> Type -> Type -> Checker Pred
compileAtType s op t1 t2 coeffTy = do
  c1 <- compileNatKindedTypeToCoeffectAtType s t1 coeffTy
  c2 <- compileNatKindedTypeToCoeffectAtType s t2 coeffTy
  case op of
    TyOpEq -> return $ Con (Eq s c1 c2 coeffTy)
    TyOpNotEq -> return $ Con (Neq s c1 c2 coeffTy)
    TyOpLesser -> return $ Con (Lt s c1 c2)
    TyOpGreater -> return $ Con (Gt s c1 c2)
    TyOpLesserEq -> return $ Con (LtEq s c1 c2)
    TyOpGreaterEq -> return $ Con (GtEq s c1 c2)
    _ -> error $ pretty s <> ": I don't know how to compile binary operator " <> pretty op
