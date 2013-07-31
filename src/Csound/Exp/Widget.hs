module Csound.Exp.Widget where

import Control.Applicative(liftA2)

import Csound.Exp.Gui
import Csound.Exp.Wrapper
import Csound.Exp.SE
import Csound.Exp.GE
import Csound.Exp.Event
import Csound.Render.Channel(flSetVal, flPrintk2, changed)

runWins :: [Win] -> GE ()
runWins = mapM_ runWin

runWin :: Win -> GE ()
runWin w = saveGuiRoot w

runFl :: Gui -> GE ()
runFl g = runWin (Win "" Nothing g)

type Reader a = SE a
type Writer a = a -> SE ()
type Inner    = SE ()

noWrite :: Writer ()
noWrite = return 

noRead :: Reader ()
noRead  = return ()

noInner :: Inner
noInner = return ()

newtype Widget a b = Widget { unWidget :: GE (GuiNode, Writer a, Reader b, Inner) }

instance Functor (Widget a) where
    fmap f (Widget x) = Widget $ fmap 
        (\(gui, writer, reader, inner) -> (gui, writer, fmap f reader, inner)) x

type Sink   a = GE (Gui, Writer a)
type Source a = GE (Gui, Reader a)
type Display  = GE Gui

mapSource :: (a -> b) -> Source a -> Source b
mapSource f = fmap $ \(gui, reader) -> (gui, fmap f reader) 

widget :: Widget a b -> GE (Gui, Writer a, Reader b)
widget a = do 
    (gui, writer, reader, inner) <- unWidget a
    appendToGui gui inner
    return (fromGuiHandle $ guiNodeHandle gui, writer, reader)

mkWidgetWith :: GE (Gui, Writer a, Reader b, Inner) -> Widget a b
mkWidgetWith elems = Widget $ do
    n <- newGuiHandle 
    (gui, writer, reader, inner) <- elems
    return (GuiNode gui n, writer, reader, inner)

sink :: Widget a b -> Sink a
sink = fmap (\(gui, writer, _) -> (gui, writer)) . widget

source :: Widget a b -> Source b
source = fmap (\(gui, _, reader) -> (gui, reader)) . widget

display :: Widget a b -> Display
display = fmap (\(gui, _, _) -> gui) . widget

mkDisplayWith :: GE (Gui, Inner) -> Widget () () 
mkDisplayWith = mkWidgetWith . fmap (\(gui, inner) -> (gui, noWrite, noRead, inner))

mkWidget :: GE (Gui, Writer a, Reader b) -> Widget a b
mkWidget = mkWidgetWith . fmap (\(a, b, c) -> (a, b, c, noInner))

mkSink :: GE (Gui, Writer a) -> Sink a
mkSink = sink . mkWidget . fmap (\(gui, writer) -> (gui, writer, noRead))

mkSource :: GE (Gui, Reader b) -> Source b
mkSource = source . mkWidget . fmap (\(gui, reader) -> (gui, noWrite, reader))
    
mkDisplay :: GE Gui -> Display
mkDisplay = display . mkWidget . fmap (\gui -> (gui, noWrite, noRead))

-----------------------------------------------------------------------------  
-- primitive elements

singleOut :: Maybe Double -> Elem -> Source Sig 
singleOut v0 el = source $ Widget $ do
    (var, handle) <- newGuiVar
    let handleVar = guiHandleToVar handle
        inits = maybe [] (return . InitMe handleVar) v0
    return ( GuiNode (fromElem [var, handleVar] inits el) handle
           , noWrite
           , readVar var
           , noInner )

singleIn :: Maybe Double -> Elem -> Sink Sig 
singleIn v0 el = sink $ Widget $ do
    (_, handle) <- newGuiVar
    let handleVar = guiHandleToVar handle        
        inits = maybe [] (return . InitMe handleVar) v0
    return $ ( GuiNode (fromElem [handleVar] inits el) handle
             , printk2 handle
             , noRead
             , noInner )

countSig :: Diap -> Step -> Maybe Step -> Double -> Source Sig
countSig diap step1 mStep2 v0 = singleOut (Just v0) $ Count diap step1 mStep2

count :: Diap -> Step -> Maybe Step -> Double -> Source (Evt D)
count diap step1 mStep2 v0 = mapSource snaps $ countSig diap step1 mStep2 v0

joy :: Span -> Span -> (Double, Double) -> Source (Sig, Sig)
joy sp1 sp2 (x, y) = source $ Widget $ do
    (var1, handle1) <- newGuiVar
    (var2, handle2) <- newGuiVar
    let handleVar1 = guiHandleToVar handle1
        handleVar2 = guiHandleToVar handle2
        outs  = [var1, var2, handleVar1, handleVar2]
        inits = [InitMe handleVar1 x, InitMe handleVar2 y]
    return ( GuiNode (fromElem outs inits (Joy sp1 sp2)) handle1
           , noWrite
           , liftA2 (,) (readVar var1) (readVar var2)
           , noInner)

knob :: Span -> Double -> Source Sig
knob sp v0 = singleOut (Just v0) $ Knob sp

roller :: Span -> Step -> Double -> Source Sig
roller sp step v0 = singleOut (Just v0) $ Roller sp step

slider :: Span -> Double -> Source Sig
slider sp v0 = singleOut (Just v0) $ Slider sp

text :: Diap -> Step -> Double -> Source Sig
text diap step v0 = singleOut (Just v0) $ Text diap step 

-- write slider

writeSlider :: Span -> Double -> GE (Gui, Writer Sig, Reader Sig)
writeSlider sp v0 = widget $ Widget $ do
    (var, handle) <- newGuiVar
    let handleVar = guiHandleToVar handle 
    return ( GuiNode (fromElem [var, handleVar] 
                               [InitMe handleVar v0] 
                               (Slider sp)) 
                     handle
           , setVal handle
           , readVar var
           , noInner )    

box :: String -> Display
box label = display $ Widget $ do
    (_, handle) <- newGuiVar
    return $ ( GuiNode (fromElem [guiHandleToVar handle] [] (Box label)) handle
             , noWrite
             , noRead
             , noInner )

button :: Source (Evt ())
button = mapSource sigToEvt buttonSig

buttonSig :: Source Sig
buttonSig = singleOut Nothing Button

toggle :: Source (Evt D)
toggle = mapSource snaps toggleSig

toggleSig :: Source Sig
toggleSig = singleOut Nothing Toggle

butBank :: Int -> Int -> Source (Evt D)
butBank xn yn = mapSource snaps $ butBankSig xn yn

butBankSig :: Int -> Int -> Source Sig 
butBankSig xn yn = singleOut Nothing $ ButBank xn yn

value :: Double -> Sink Sig 
value v = singleIn (Just v) Value

meter :: Span -> Double -> Sink Sig
meter sp v = singleIn (Just v) (Slider sp)

-- writers

refHandle :: GuiHandle -> SE D
refHandle h = readVar (guiHandleToVar h)

setVal :: GuiHandle -> Sig -> SE ()
setVal handle val = flSetVal (changed [val]) val =<< refHandle handle

printk2 :: GuiHandle -> Sig -> SE ()
printk2 handle val = flPrintk2 val =<< refHandle handle
