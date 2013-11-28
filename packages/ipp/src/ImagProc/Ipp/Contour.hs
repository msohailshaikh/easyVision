-----------------------------------------------------------------------------
{- |
Module      :  ImagProc.Ipp.Contour
Copyright   :  (c) Alberto Ruiz 2007-13
License     :  GPL

Maintainer  :  Alberto Ruiz (aruiz at um dot es)
Stability   :  provisional

Contour Extraction.

-}
-----------------------------------------------------------------------------

module ImagProc.Ipp.Contour (
    -- * Extraction
    contours,
    otsuContours,
    localContours,
    -- * Devel
    rawContours,
    rawContour,
    contourAt
)
where

import Image.Devel
import ImagProc.Ipp.Pure
import ImagProc.Ipp.AdHoc
import ImagProc.Ipp.Generic
import Util.Geometry(Polyline(..))
import ImagProc.Ipp.Core
import Foreign.C.Types(CUChar)
import System.IO.Unsafe(unsafePerformIO)
import Debug.Trace
import Data.List(sortBy, maximumBy, zipWith4, sort,foldl', tails)
import Numeric.LinearAlgebra hiding (constant)
import Numeric.LinearAlgebra.Util(diagl)
import Util.Homogeneous
import Util.Rotation
import Util.Misc(degree,debug)
import Numeric.GSL.Polynomials(polySolve)
import Numeric.GSL.Fourier(ifft)



data Dir = ToRight | ToLeft | ToDown | ToUp deriving Eq
nextPos :: Image I8u -> I8u -> (Pixel,Dir) -> (Pixel,Dir)

nextPos im v (Pixel r c, ToRight) = case (a,b) of
    (False,False) -> (Pixel (r+1) c, ToDown)
    (False,True)  -> (Pixel r (c+1), ToRight)
    _             -> (Pixel (r-1) c, ToUp)
  where
    a = readPixel im (Pixel (r-1) c) == v
    b = readPixel im (Pixel r c) == v

nextPos im v (Pixel r c, ToDown) = case (a,b) of
    (False,False) -> (Pixel r (c-1), ToLeft)
    (False,True)  -> (Pixel (r+1) c, ToDown)
    _             -> (Pixel r (c+1), ToRight)
  where
    a = readPixel im (Pixel r c) == v
    b = readPixel im (Pixel r (c-1)) == v

nextPos im v (Pixel r c, ToLeft) = case (a,b) of
    (False,False) -> (Pixel (r-1) c, ToUp)
    (False,True)  -> (Pixel r (c-1), ToLeft)
    _             -> (Pixel (r+1) c, ToDown)
  where
    a = readPixel im (Pixel r (c-1)) == v
    b = readPixel im (Pixel (r-1) (c-1)) == v

nextPos im v (Pixel r c, ToUp) = case (a,b) of
    (False,False) -> (Pixel r (c+1), ToRight)
    (False,True)  -> (Pixel (r-1) c, ToUp)
    _             -> (Pixel r (c-1), ToLeft)
  where
    a = readPixel im (Pixel (r-1) (c-1)) == v
    b = readPixel im (Pixel (r-1) c) == v


-- | extracts a contour with given value from an image.
--   Don't use it if the region touches the limit of the image ROI.
rawContour :: ImageGray -- ^ source image
           -> Pixel     -- ^ starting point of the contour (a top-left corner)
           -> I8u    -- ^ pixel value of the region (typically generated by some kind of floodFill or thresholding)
           -> [Pixel]   -- ^ contour of the region
rawContour im start v = clean $ iterate (nextPos im v) (start, ToRight)
    where clean ((a,_):rest) = a : clean' a rest
          clean' p ((v1,s1):rest@((v2,s2):_))
            | p  == v1  = []
  --          | s1 == s2  = clean' p rest
            | otherwise = v1: clean' p rest


cloneClear im = return (copy (constant zeroP (size im)) [(im,topLeft (roi im))])


-- | extracts contours of active regions (255) from a binary image
rawContours :: Int       -- ^ maximum number of contours
         -> Int       -- ^ minimum area (in pixels) of the admissible contours
         -> ImageGray -- ^ image source
         -> [([Pixel],Int,ROI)]  -- ^ list of contours, with area and ROI
rawContours n d im = unsafePerformIO $ do
    aux <- cloneClear im
    r <- auxCont n d aux
    return r



auxCont n d aux = do
    let (v,p) = maxIndx8u aux
    if n==0 || (v<255)
        then return []
        else do
            (r@(ROI r1 r2 c1 c2),a,_) <- floodFill8u aux p 128
            let ROI lr1 lr2 lc1 lc2 = roi aux
            if a < d || r1 == lr1 || c1 == lc1 || r2 == lr2 || c2 == lc2
                    then auxCont n d aux
                    else do
                    let c = rawContour aux p 128
                    rest <- auxCont (n-1) d aux
                    return ((c,a,r):rest)


contourAt :: Int -> ImageGray -> Pixel -> Maybe [Pixel]
contourAt dif img start = unsafePerformIO $ do
    aux <- cloneClear (median Mask5x5 img)
    let ROI lr1 lr2 lc1 lc2 = roi aux
        d = fromIntegral dif
    (r@(ROI r1 r2 c1 c2),a,_) <- floodFill8uGrad aux start d d 0
    let st = findStart aux start
        touches = r1 == lr1 || c1 == lc1 || r2 == lr2 || c2 == lc2
        pol = if not touches
                then Just (rawContour aux st 0)
                else Nothing
    return pol

findStart im = fixp (findLimit im left . findLimit im top)

findLimit im dir pix
    | readPixel im neig == 0 = findLimit im dir neig
    | otherwise          = pix
  where neig = dir pix

top  (Pixel r c) = Pixel (r-1) c
left (Pixel r c) = Pixel r (c-1)

fixp f p = if s == p then p else fixp f s
    where s = f p



-- | extracts contours of active regions (255) from a binary image
contours :: Int         -- ^ maximum number of contours
         -> Int         -- ^ minimum area (in pixels) of the admissible contours
         -> ImageGray   -- ^ image source
         -> [Polyline]
contours nc ma x = map proc . rawContours nc ma $ x
  where
    fst3 (a,_,_) = a
    proc = Closed . pixelsToPoints (size x) . fst3


--------------------------------------------------------------------------------

otsuContours :: ImageGray -> [Polyline]
-- ^ extract dark contours with Otsu threshold
otsuContours x = contours 1000 100 otsu
  where
    otsu = compareC8u (otsuThreshold x) IppCmpLess x

--------------------------------------------------------------------------------

-- | extract contours (dark,light) with adaptive local binarization
localContours :: I8u         -- ^ contrast
              -> Int         -- ^ minimum length
              -> ImageGray   -- ^ input image
              -> ([Polyline],[Polyline])  -- ^ (black, white)
localContours rth len g = (cs difB, cs difW)
  where
    gmx  = filterMax8u 4 g
    gmn  = filterMin8u 4 g
    th   = add8u 1 gmx gmn

    mx   = dilate3x3 g
    mn   = erode3x3  g
    mask = compareC8u rth IppCmpGreaterEq (sub8u 0 mx mn)
    
    difW = compare8u IppCmpGreater g th
    difB = compare8u IppCmpLess    g th
    
    cs dif = filter good $ rcs
      where
        rcs = contours 1000 len $ dif `andI` mask
        good = ok . head . pointsToPixels (size dif) . polyPts

    ok p = readPixel mx p > readPixel th p && readPixel mn p < readPixel th p

