{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Language.Granule.Synthesis.RewriteHoles where

import Control.Arrow (second)
import Control.Exception (SomeException, throwIO, try)
import Control.Monad (when, void)
import Data.Maybe (fromJust)
import qualified Data.Text.Lazy as Text
import System.Directory (removeFile, renameFile)
import System.FilePath (splitFileName)
import System.IO (hClose, hPutStr, openTempFile)
import Text.Reprinter

import Language.Granule.Syntax.Def
import Language.Granule.Syntax.Expr
import Language.Granule.Syntax.Pattern
import Language.Granule.Syntax.Pretty
import Language.Granule.Syntax.Identifiers

import Language.Granule.Utils

{-
  = HoleMessage
    { errLoc :: Span , holeTy :: Type, context :: Ctxt Assumption, tyContext :: Ctxt (Kind, Quantifier), cases :: }
-}
rewriteHole ::
     (?globals :: Globals) => String -> AST () () -> Bool -> ([Id], [[Pattern ()]]) -> IO ()
rewriteHole input ast keepBackup cases = do
  let source = Text.pack input
  let refactored = rewriteHoles source (snd cases) ast
  if False
    then void . putStrLn . Text.unpack $ refactored
    else do
      -- Note: this is all copied from Preprocessor.hs, abstract into Utils
      let file = fromJust $ globalsSourceFilePath ?globals
      -- open a temporary file
      (tempFile, tempHd) <- uncurry openTempFile (splitFileName file)
            -- write the processed source to the temporary file
      try (hPutStr tempHd (Text.unpack refactored)) >>= \case
        Right () -> do
          hClose tempHd
          -- if we are keeping the original source file, then rename it
          when keepBackup (renameFile file (file <> ".bak"))
          -- move the temp file to the original source file path
          renameFile tempFile file
          return ()
        Left (e :: SomeException) -> do
          hClose tempHd
          removeFile tempFile
          throwIO e

astReprinter :: (?globals :: Globals) => Reprinting Identity
astReprinter = catchAll `extQ` reprintExpr
  where
    reprintExpr x = genReprinting (return . Text.pack . pretty) (x :: Def () ())

-- Converts e.g. {! x !} to ? and replicates equation for each pattern
-- TODO: Support nested holes
-- TODO: Holes inside Val e.g. lambda
-- TODO: Support multiple equations before refactor
rewriteHoles ::
     (?globals :: Globals) => Source -> [[Pattern ()]] -> AST () () -> Source
rewriteHoles source cases =
  runIdentity . (\ast -> reprint astReprinter ast source) . holeRefactor cases

holeRefactor :: [[Pattern ()]] -> AST () () -> AST () ()
holeRefactor cases ast =
  ast {definitions = map (holeRefactorDef cases) (definitions ast)}

holeRefactorDef :: [[Pattern ()]] -> Def () () -> Def () ()
holeRefactorDef cases def =
  def {defEquations = updateEquations (defEquations def), defRefactored = True}
  where
    updateEquations [eqn] =
      let updated = holeRefactorEqn eqn
      in map
           (\cas -> (\pats eqn -> eqn {equationPatterns = pats}) cas updated)
           cases
    updateEquations _ = error "Only one LHS for now"

holeRefactorEqn :: Equation () () -> Equation () ()
holeRefactorEqn eqn = eqn {equationBody = holeRefactorExpr (equationBody eqn)}

holeRefactorExpr :: Expr () () -> Expr () ()
holeRefactorExpr (Hole sp a _ _) = Hole sp a True []
holeRefactorExpr (App sp a rf e1 e2) =
  App sp a rf (holeRefactorExpr e1) (holeRefactorExpr e2)
holeRefactorExpr (Binop sp a rf op e1 e2) =
  Binop sp a rf op (holeRefactorExpr e1) (holeRefactorExpr e2)
holeRefactorExpr (LetDiamond sp a rf pat ty e1 e2) =
  LetDiamond sp a rf pat ty (holeRefactorExpr e1) (holeRefactorExpr e2)
holeRefactorExpr (Case sp a rf e cases) =
  Case sp a rf (holeRefactorExpr e) (map (second holeRefactorExpr) cases)
holeRefactorExpr v@Val {} = v
