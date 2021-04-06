{-# options_ghc -fno-warn-incomplete-uni-patterns -Wno-deprecations #-}

module Language.Granule.Checker.Ghost where

import Language.Granule.Context
import Language.Granule.Syntax.Identifiers
import Language.Granule.Syntax.Type
import Language.Granule.Checker.Monad

import Data.List (partition)

allGhostVariables :: Ctxt Assumption -> Ctxt Assumption
allGhostVariables = filter isGhost

freshGhostVariableContext :: Checker (Ctxt Assumption)
freshGhostVariableContext = do
  -- TODO: fix this, don't specialize ghost to level kind
  return [(mkId ".var.ghost",
           Ghost (tyCon "Private"))]
           -- Ghost (TyGrade Nothing 0))]

ghostVariableContextMeet :: Ctxt Assumption -> Checker (Ctxt Assumption)
ghostVariableContextMeet env =
  -- let (ghosts,env') = partition isGhost env
  --     newGrade      = foldr (TyInfix TyOpMeet) (tyCon "Unused") $ map ((\(Ghost ce) -> ce) . snd) ghosts
  -- in return $ (mkId ".var.ghost", Ghost newGrade) : env'
  let (ghosts,env') = partition isGhost env
      newGrade      = foldr1 (TyInfix TyOpMeet) $ map ((\(Ghost ce) -> ce) . snd) ghosts
  -- if there's no ghost variable in env, don't add one
  in if null ghosts then return env' else return $ (mkId ".var.ghost", Ghost newGrade) : env'

isGhost :: (a, Assumption) -> Bool
isGhost (_, Ghost _) = True
isGhost _ = False
