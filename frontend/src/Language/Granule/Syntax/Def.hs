{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances #-}

module Language.Granule.Syntax.Def where

import Data.List ((\\), delete)
import Data.Set (Set)
import GHC.Generics (Generic)

import Language.Granule.Context (Ctxt)
import Language.Granule.Syntax.FirstParameter
import Language.Granule.Syntax.Helpers
import Language.Granule.Syntax.Identifiers
import Language.Granule.Syntax.Span
import Language.Granule.Syntax.Expr
import Language.Granule.Syntax.Type
import Language.Granule.Syntax.Pattern

-- | Top-level ASTs
-- | Comprise a list of data type declarations and a list
-- | of expression definitions
-- | where `v` is the type of values and `a` annotations
data AST v a = AST [DataDecl] [Def v a] [Interface] [Instance v a] (Set Import)
deriving instance (Show v, Show a) => Show (AST v a)
deriving instance (Eq v, Eq a) => Eq (AST v a)

type Import = FilePath

-- | Function definitions
data Def v a = Def
  { defSpan :: Span
  , defId :: Id
  , defEquations :: [Equation v a]
  , defTypeScheme :: TypeScheme
  }
  deriving Generic

deriving instance (Show v, Show a) => Show (Def v a)
deriving instance (Eq v, Eq a) => Eq (Def v a)

-- | Single equation of a function
data Equation v a =
    Equation Span a [Pattern a] (Expr v a)
  deriving Generic
deriving instance (Show v, Show a) => Show (Equation v a)
deriving instance (Eq v, Eq a) => Eq (Equation v a)

instance FirstParameter (Def v a) Span
instance FirstParameter (Equation v a) Span

-- | Data type declarations
data DataDecl = DataDecl
  { dataDeclSpan :: Span
  , dataDeclId :: Id
  , dataDeclTyVarCtxt :: Ctxt Kind
  , dataDeclKindAnn :: Maybe Kind
  , dataDeclDataConstrs :: [DataConstr]
  }
  deriving (Generic, Show, Eq)

instance FirstParameter DataDecl Span

-- | Data constructors
data DataConstr
  = DataConstrIndexed
    { dataConstrSpan :: Span, dataConstrId :: Id, dataConstrTypeScheme :: TypeScheme } -- ^ GADTs
  | DataConstrNonIndexed
    { dataConstrSpan :: Span, dataConstrId :: Id, dataConstrParams :: [Type] } -- ^ ADTs
  deriving (Eq, Show, Generic)

nonIndexedToIndexedDataConstr :: Id -> [(Id, Kind)] -> DataConstr -> DataConstr
nonIndexedToIndexedDataConstr _     _      d@DataConstrIndexed{} = d
nonIndexedToIndexedDataConstr tName tyVars (DataConstrNonIndexed sp dName params)
    -- Don't push the parameters into the type scheme yet
    = DataConstrIndexed sp dName (Forall sp [] [] ty)
  where
    ty = foldr FunTy (returnTy (TyCon tName) tyVars) params
    returnTy t [] = t
    returnTy t (v:vs) = returnTy (TyApp t ((TyVar . fst) v)) vs

instance FirstParameter DataConstr Span

-- | How many data constructors a type has (Nothing -> don't know)
type Cardinality = Maybe Nat


-- | Interfaces.
data Interface =
  Interface
  Span
  Id           -- ^ interface name
  [TConstraint] -- ^ constraints
  [(Id, Maybe Kind)] -- ^ parameters
  [InterfaceMethod]
  deriving (Show, Eq)


interfaceId :: Interface -> Id
interfaceId (Interface _ n _ _ _) = n


interfaceSpan :: Interface -> Span
interfaceSpan (Interface sp _ _ _ _) = sp


-- | Interface methods (method type signatures).
data InterfaceMethod = InterfaceMethod Span Id TypeScheme
  deriving (Generic, Show, Eq)

instance FirstParameter InterfaceMethod Span


-- | Instances.
data Instance v a =
  Instance
  Span
  Id         -- ^ interface name
  [TConstraint] -- ^ constraints
  InstanceTypes   -- ^ instance type
  [InstanceEquation v a] -- ^ implementations

deriving instance (Eq v, Eq a) => Eq (Instance v a)
deriving instance (Show v, Show a) => Show (Instance v a)

-- | A single equation in an instance.
data InstanceEquation v a = InstanceEquation Span (Maybe Id) (Equation v a)
  deriving (Generic)

instance FirstParameter (InstanceEquation v a) Span
deriving instance (Eq v, Eq a) => Eq (InstanceEquation v a)
deriving instance (Show v, Show a) => Show (InstanceEquation v a)


-- | The parameters of an instance.
data InstanceTypes = InstanceTypes Span [Type]
  deriving (Show, Generic, Eq)

instance FirstParameter InstanceTypes Span


-- | Fresh a whole AST
freshenAST :: AST v a -> AST v a
freshenAST (AST dds defs ifaces insts imports) =
  AST dds' defs' ifaces' insts' imports
    where dds' = map runFreshener dds
          defs' = map runFreshener defs
          ifaces' = map runFreshener ifaces
          insts' = map runFreshener insts

instance Monad m => Freshenable m DataDecl where
  freshen (DataDecl s v tyVars kind ds) = do
    tyVars <- mapM (\(v, k) -> freshen k >>= \k' -> return (v, k')) tyVars
    kind <- freshen kind
    ds <- freshen ds
    return $ DataDecl s v tyVars kind ds

instance Monad m => Freshenable m DataConstr where
  freshen (DataConstrIndexed sp v tys) = do
    tys <- freshen tys
    return $ DataConstrIndexed sp v tys
  freshen (DataConstrNonIndexed sp v ts) = do
    ts <- mapM freshen ts
    return $ DataConstrNonIndexed sp v ts

instance Monad m => Freshenable m Interface where
  freshen (Interface sp iname constrs params itys) = do
    params' <- mapM (both (freshIdentifierBase Type) freshen) params
    constrs' <- mapM freshen constrs
    itys' <- mapM freshen itys
    return $ Interface sp iname constrs' params' itys'
    where both x y (z1,z2) = x z1 >>= (\z1' -> fmap ((,) z1') (y z2))

instance Monad m => Freshenable m InterfaceMethod where
  freshen (InterfaceMethod sp name tys) = do
    tys' <- freshen tys
    return $ InterfaceMethod sp name tys'

instance Monad m => Freshenable m (Instance v a) where
  freshen (Instance sp name constrs idat defs) = do
    idat' <- freshen idat
    constrs' <- mapM freshen constrs
    defs' <- mapM freshen defs
    return $ Instance sp name constrs' idat' defs'

instance Monad m => Freshenable m (InstanceEquation v a) where
  freshen (InstanceEquation sp name eqn) = do
    eqn' <- freshen eqn
    return $ InstanceEquation sp name eqn'

instance Monad m => Freshenable m InstanceTypes where
  freshen (InstanceTypes sp tys) = do
    mapM_ (freshIdentifierBase Type) (concatMap freeVars tys)
    tys' <- freshen tys
    return $ InstanceTypes sp tys'

instance Monad m => Freshenable m (Equation v a) where
  freshen (Equation s a ps e) = do
    ps <- mapM freshen ps
    e <- freshen e
    return (Equation s a ps e)

-- | Alpha-convert all bound variables of a definition to unique names.
instance Monad m => Freshenable m (Def v a) where
  freshen (Def s var eqs t) = do
    t  <- freshen t
    eqs <- mapM freshen eqs
    return (Def s var eqs t)

instance Term (Equation v a) where
  freeVars (Equation s a binders body) =
      freeVars body \\ concatMap boundVars binders

instance Term (Def v a) where
  freeVars (Def _ name equations _) =
    delete name (concatMap freeVars equations)
