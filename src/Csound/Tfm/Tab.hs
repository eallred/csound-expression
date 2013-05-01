module Csound.Tfm.Tab(
    tabMap,
    substInstrTabs, substNoteTabs, 
    defineInstrTabs, defineNoteTabs,
    updateTabSize
) where

import qualified Data.Map as M(fromList, (!))
import qualified Data.IntMap as IM(findWithDefault)

import Data.Fix(Fix(..), cata)
import Data.List(nub)
import Data.Foldable(foldMap)

import Csound.Exp

----------------------------------------------------------------------------
-- Collects all tables from instruments [E] and notes [Prim]
--
tabMap :: [E] -> [Prim] -> TabMap
tabMap es ps = M.fromList $ zip (nub $ (getPrimTabs =<< ps) ++ (getInstrTabs =<< es)) [1 ..]
    
getInstrTabs :: E -> [LowTab]
getInstrTabs = cata $ \re -> (maybe [] id $ ratedExpDepends re) ++ case fmap fromPrimOr $ ratedExpExp re of    
    ExpPrim p -> getPrimTabs p
    Tfm _ as -> concat as
    ConvertRate _ _ a -> a
    ExpNum a -> foldMap id a
    Select _ _ a -> a
    If info a b -> foldMap id info ++ a ++ b
    ReadVar _ -> []
    WriteVar _ a -> a
    where fromPrimOr x = case unPrimOr x of
            Left  p -> getPrimTabs p
            Right a -> a

getPrimTabs :: Prim -> [LowTab]
getPrimTabs x = case x of
    PrimTab (Right t) -> [t]
    _ -> []

----------------------------------------------------------------------------
-- We substitute tables with their unique identifiers. TabMap defines the identifiers.

-- substitutes tables in the instruments (orchestra)
substInstrTabs :: TabMap -> E -> E
substInstrTabs m = cata $ \re -> Fix $ re { ratedExpExp = fmap phi $ ratedExpExp re }
    where phi x = case unPrimOr x of
            Left p -> PrimOr $ Left $ substPrimTab m p
            _ -> x 

-- substitutes tables in the notes (score)
substNoteTabs :: TabMap -> Note -> Note
substNoteTabs m = fmap (substPrimTab m)

-- substitute table in the primitive value.
substPrimTab :: TabMap -> Prim -> Prim
substPrimTab m x = case x of 
    PrimTab (Right tab) -> PrimInt (m M.! tab)
    _ -> x

----------------------------------------------------------------------------
-- Defining tables
--
-- To define table means to transform all relative parameters to absolute.
-- Relative parameters (size or points in the case of tables for interpolation)
-- are set from renderer settings. User can change them globally.
--

-- defines tables for an instrument
defineInstrTabs :: TabFi -> E -> E
defineInstrTabs n = cata $ \re -> Fix $ re { ratedExpExp = fmap phi $ ratedExpExp re }
    where phi x = case unPrimOr x of
            Left p -> PrimOr $ Left $ definePrimTab n p
            _ -> x 

-- define tables for a note
defineNoteTabs :: TabFi -> Note -> Note
defineNoteTabs n = fmap (definePrimTab n)

-- define table for a primitive value
definePrimTab :: TabFi -> Prim -> Prim
definePrimTab n x = case x of
    PrimTab (Left tab) -> PrimTab (Right $ defineTab n tab)
    _ -> x

-- set all relative parameters to absolute. 
defineTab :: TabFi -> Tab -> LowTab
defineTab tabFi tab = LowTab size (tabGen tab) args
    where size = defineTabSize (getTabSizeBase tabFi tab) (tabSize tab)
          args = defineTabArgs size (tabArgs tab)

getTabSizeBase :: TabFi -> Tab -> Int
getTabSizeBase tf tab = IM.findWithDefault (tabFiBase tf) (tabGen tab) (tabFiGens tf)

defineTabArgs :: Int -> TabArgs -> [Double] 
defineTabArgs size args = case args of
    ArgsPlain as -> as 
    ArgsRelative as -> fromRelative size as
    where fromRelative n as = substEvens (mkRelative n $ getEvens as) as
          getEvens xs = case xs of
            [] -> []
            a:[] -> []
            a:b:as -> b : getEvens as
            
          substEvens evens xs = case (evens, xs) of
            ([], xs) -> xs
            (es, []) -> []
            (e:es, a:b:as) -> a : e : substEvens es as
            
          mkRelative n as = fmap (fromIntegral . round . (s * )) as
            where s = fromIntegral n / sum as
            

defineTabSize :: Int -> TabSize -> Int
defineTabSize base x = case x of
       SizePlain n -> n
       SizeDegree guardPoint degree ->          
                byGuardPoint guardPoint $
                byDegree base degree
    where byGuardPoint guardPoint 
            | guardPoint = (+ 1)
            | otherwise  = id
            
          byDegree base n = 2 ^ max 0 (base + n) 

----------------------------------------------------------------------------
-- change table size

updateTabSize :: (TabSize -> TabSize) -> Tab -> Tab
updateTabSize phi x = case x of
    TabExp _ -> error "you can change size only for primitive tables (made with gen-routines)"
    primTab  -> primTab{ tabSize = phi $ tabSize primTab }

