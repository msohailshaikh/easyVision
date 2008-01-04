-----------------------------------------------------------------------------
{- |
Module      :  Ipp.ImageProcessing
Copyright   :  (c) Alberto Ruiz 2006
License     :  GPL-style

Maintainer  :  Alberto Ruiz (aruiz at um dot es)
Stability   :  very provisional
Portability :  hmm...

A collection of frequently used image processing functions.

-}
-----------------------------------------------------------------------------

module ImagProc.ImageProcessing (
-- * IPP auxiliary structures
  Mask(..)
, IppCmp(..)
, AlgHint(..)
-- * Utilities
, jaehne32f
, set32f, set8u, set8u3
, copyROI32f, copyROI32f'
--, copyROI8u, 
, copyROI8u', copyROI8u3'
, times
, partit
-- * Image manipulation
, yuvToRGB
, yuvToRGB_P
, yuvToGray
, yuvToYUV_P
, rgbToGray
, grayToYUV
, rgbToYUV
, rgbToHSV, hsvCode, hsvCodeTest
, hsvToRGB
, scale8u32f
, scale32f8u
, copy32f
, copy8u
, copy8uC3
, getChannel
, putChannels
, copyMask32f
, resize32f, resize8u, resize8u3
, warpOn32f, warpOn8u, warpOn8u3
-- * Image arithmetic
, scale32f
, mul32f, add32f, sub32f
, sub8u
, absDiff8u, absDiff32f
, sum8u, sum32f
, abs32f, sqrt32f
, compare32f
, thresholdVal32f
, thresholdVal8u
, binarize8u
, minmax
, maxIndx
, maxIndx8u
, integral
, histogram, histogramN
-- * Basic image processing
, gauss
, laplace
, highPass8u
, median
, dilate3x3 --, dilate
, erode3x3  --, erode
, not8u, and8u, or8u
, sobelVert, sobelHoriz
, secondOrder
, hessian
, filterMax32f
, localMax
, getPoints32f
-- * Frequential Analysis
, dct, idct
, genFFT, FFTNormalization(..), magnitudePack, powerSpectrum
-- * Computation of interest points
, getCorners
-- * Edges
, canny
-- * Distance Transform
, distanceTransform
-- * Connected Components
, floodFill8u, floodFill8uGrad
-- * Local Binary Patterns
, lbp, lbpN
-- * Geometric Transform Functions
, mirror8u
)
where

import ImagProc.Ipp
import Foreign hiding (shift)
import Foreign.C.Types(CUChar)
import Vision --hiding ((|-|),(|+|))
import Numeric.LinearAlgebra
import Numeric

---------------------------------------

imgAsR1 roifun im = do 
    r <- imgAs im
    return r {vroi = roifun (vroi im)}

cr1 f im r = f // src im (vroi r) // dst r (vroi r)

imgAsR2 roifun im1 im2 = do 
    r <- imgAs im1
    return r {vroi = roifun (vroi im1) (vroi im2)}

cr2 f im1 im2 r = f // src im1 (vroi r) // src im2 (vroi r)// dst r (vroi r)

----------------------------------------

-- | Writes into a existing image a desired value in a specified roi.
set32f :: Float      -- ^ desired value
       -> ROI        -- ^ roi
       -> ImageFloat -- ^ destination image
       -> IO ()
set32f v roi (F im) = ippiSet_32f_C1R v // dst im roi // checkIPP "set32f" [im]

-- | Writes into a existing image a desired value in a specified roi.
set8u :: CUChar      -- ^ desired value
       -> ROI        -- ^ roi
       -> ImageGray  -- ^ destination image
       -> IO ()
set8u v roi (G im) = ippiSet_8u_C1R v // dst im roi // checkIPP "set8u" [im]


-- | Writes into a existing image a desired value in a specified roi.
set8u3 :: CUChar -> CUChar -> CUChar -- ^ desired RGB value
       -> ROI        -- ^ roi
       -> ImageRGB   -- ^ destination image
       -> IO ()
set8u3 r g b roi (C im) = do
    v <- mallocArray 3
    pokeArray v [r,g,b]
    ippiSet_8u_C3R v // dst im roi // checkIPP "set8u3" [im]
    free v


-- | Creates a 8u Gray image from a 8uC3 RGB image
rgbToGray :: ImageRGB      -- ^ input image
          -> IO ImageGray  -- ^ result
rgbToGray (C im) = do
    r' <- img Gray (isize im)
    let r = r' {vroi = vroi im}
    cr1 ippiRGBToGray_8u_C3C1R im r // checkIPP "RGBToGray" [im]
    return (G r)

-- | Converts a rgb image into a HSV image
rgbToHSV :: ImageRGB      -- ^ input image
          -> IO ImageRGB  -- ^ hmm... result
rgbToHSV (C im) = do
    C r' <- image (isize im)
    let r = r' {vroi = vroi im}
    cr1 ippiRGBToHSV_8u_C3R im r // checkIPP "RGBToHSV" [im]
    return (C r)

-- | Converts a rgb image into a HSV image
hsvToRGB :: ImageRGB      -- ^ input image
         -> IO ImageRGB  -- ^ hmm... result
hsvToRGB (C im) = do
    C r' <- image (isize im)
    let r = r' {vroi = vroi im}
    cr1 ippiHSVToRGB_8u_C3R im r // checkIPP "HSVToRGB" [im]
    return (C r)


-- | Creates a 8uC3R RGB image from a YUV420 image (typically generated by a MPlayer camera). TODO : only ROI
yuvToRGB :: ImageYUV     -- ^ input image
         -> IO ImageRGB  -- ^ result
yuvToRGB (Y im) = do
    r' <- img RGB (isize im)
    let r = r' {vroi = vroi im}
    psrc  <- mallocArray 3
    let Size h w = isize im
    let ps = castPtr (ptr im) :: Ptr CUChar
    pokeArray psrc [ps, ps `advancePtr` (h*w), ps `advancePtr` (h*w + h*w `div` 4)]
    pstep <- mallocArray 3
    pokeArray pstep [w, w`div`2, w`div`2]
    ippiYUV420ToRGB_8u_P3C3R (castPtr psrc) pstep (ptr r) (step r) (roiSize (fullroi r)) // checkIPP "yuvToRGB" [im]
    free psrc
    free pstep
    return (C r)


-- | Creates  a YUV420 image (typically generated by a MPlayer camera) from a 8uC3R RGB image. TODO : only ROI
rgbToYUV :: ImageRGB     -- ^ input image
         -> IO ImageYUV  -- ^ result
rgbToYUV (C im) = do
    r' <- img YUV (isize im)
    let r = r' {vroi = vroi im}
    pdst  <- mallocArray 3
    let Size h w = isize im
    let ps = castPtr (ptr r) :: Ptr CUChar
    pokeArray pdst [ps, ps `advancePtr` (h*w), ps `advancePtr` (h*w + h*w `div` 4)]
    pstep <- mallocArray 3
    pokeArray pstep [w, w`div`2, w`div`2]
    ippiRGBToYUV420_8u_C3P3R (ptr im) (step im) (castPtr pdst) pstep (roiSize (fullroi r)) // checkIPP "rgbToYUV" [im]
    free pdst
    free pstep
    return (Y r)


-- | Creates 3 8uC1R images for the R, G and B channels of a YUV420 image (typically generated by a MPlayer camera). TODO: only ROI
yuvToRGB_P :: ImageYUV     -- ^ input image
           -> IO (ImageGray,ImageGray,ImageGray)  -- ^ R,G,B channels
yuvToRGB_P (Y im) = do
    r' <- img Gray (isize im)
    let r = r' {vroi = vroi im}
    g' <- img Gray (isize im)
    let g = g' {vroi = vroi im}
    b' <- img Gray (isize im)
    let b = b' {vroi = vroi im}
    psrc  <- mallocArray 3
    let Size h w = isize im
    let ps = castPtr (ptr im) :: Ptr CUChar
    pokeArray psrc [ps, ps `advancePtr` (h*w), ps `advancePtr` (h*w + h*w `div` 4)]
    pstep <- mallocArray 3
    pokeArray pstep [w, w`div`2, w`div`2]
    pdest <- mallocArray 3
    pokeArray pdest [ptr r, ptr g, ptr b]
    ippiYUV420ToRGB_8u_P3R (castPtr psrc) pstep (castPtr pdest) (step r) (roiSize (fullroi r)) // checkIPP "yuvToRGB_P" [im]
    free psrc
    free pstep
    free pdest
    return (G r, G g, G b)

-- | Creates a 8u gray image from a YUV420 image (typically generated by a MPlayer camera)
yuvToGray :: ImageYUV       -- ^ input image
          -> IO ImageGray  -- ^ result
yuvToGray (Y im) = return (G im {layers = 1, itype = Gray, step = width (isize im)})

-- | the inverse of yuvToGray (the U and V channels are filled with 128).
grayToYUV :: ImageGray       -- ^ input image
          -> IO ImageYUV     -- ^ result
grayToYUV (G im) = do
    res <- img YUV (isize im)
    let Size h w = isize im
        tot = h*w `div` 2
    z@(G zero) <- image (Size 1 tot) -- hack to clear memory
    set8u 128 (theROI z) z
    copyBytes (ptr res `plusPtr` (h*w)) (ptr zero) tot
    copyBytes (ptr res) (ptr im) (h*step im)
    touchForeignPtr (fptr im)
    return (Y res)


-- | Creates three 8u images with the Y,U and V components from a YUV420 image (typically generated by a MPlayer camera). The U and V components are half size.
yuvToYUV_P :: ImageYUV       -- ^ input image
           -> IO (ImageGray,ImageGray,ImageGray)  -- ^ result (Y,U,V)
yuvToYUV_P (Y im) = do
    let Size h w = isize im
    let ROI r1 r2 c1 c2 = vroi im
    y' <- img Gray (isize im)
    let y = y' {vroi = vroi im, fptr = fptr im, ptr = ptr im}
    u' <- img Gray (Size (h `div` 2) (w `div` 2))
    let u = u' {vroi = ROI (r1 `div` 2) (r2 `div` 2) (c1 `div` 2) (c2 `div` 2) ,
                fptr = fptr im, ptr = ptr im `plusPtr` (h*w)}
    v' <- img Gray (isize u)
    let v = v' {vroi = vroi u,
                fptr = fptr im,
                ptr = ptr im `plusPtr` (h*w + h*w `div` 4)}
    return (G y, G u, G v)


-- | Creates a 32f image from an 8u image.
scale8u32f :: Float             -- ^ desired value corresponding to 0
           -> Float             -- ^ desired value corresponding to 255
           -> ImageGray         -- ^ input image
           -> IO ImageFloat     -- ^ result
scale8u32f vmin vmax (G im) = do
    r' <- img I32f (isize im)
    let r = r' {vroi = vroi im}
    (cr1 ippiScale_8u32f_C1R im r) vmin vmax // checkIPP "scale8u32f" [im]
    return (F r)

-- | Creates a 8u image from an 32f image.
scale32f8u :: Float             -- ^ desired value corresponding to 0
           -> Float             -- ^ desired value corresponding to 255
           -> ImageFloat        -- ^ input image
           -> IO ImageGray      -- ^ result
scale32f8u vmin vmax (F im) = do
    r' <- img Gray (isize im)
    let r = r' {vroi = vroi im}
    (cr1 ippiScale_32f8u_C1R im r) vmin vmax // checkIPP "scale32f8u" [im]
    return (G r)

-- | Creates an integral (cumulative sum) 32f image from an 8u image. Obtains a roi of the same size, but each pixel has the sum of the pixels strictly less than its position, so the first row and column contains zeroes and the last ones are not taken into account (sorry for the sentence).
integral :: ImageGray -> IO ImageFloat
integral (G im) = do
    r' <- img I32f (isize im)
    -- strange roi ...
    let ROI r1 r2 c1 c2 = vroi im
    let roi = ROI r1 (r2-1) c1 (c2-1)-- `intersection` vroi r'
    let r = r' {vroi = roi}
    (cr1 ippiIntegral_8u32f_C1R im r) 0 // checkIPP "integral" [im]
    return (F r {vroi = vroi im})


-- | Copies a given region of the input image into a destination image.
copyROI32f :: ImageFloat -- ^ input image
           -> ROI        -- ^ region to copy
           -> ImageFloat -- ^ destination image
           -> IO ()
copyROI32f (F im) roi (F r) = ippiCopy_32f_C1R // src im roi // dst r roi // checkIPP "copyROI32f" [im]

-- | Copies the roi of the input image into the roi of the destination image.
copyROI32f' :: ImageFloat -- ^ input image
            -> ROI
            -> ImageFloat -- ^ destination image
            -> ROI
            -> IO ()
copyROI32f' (F im) r1 (F r) r2 = ippiCopy_32f_C1R // src im r1 // dst r r2 // checkIPP "copyROI32f'" [im]



-- | Copies the roi of the input image into the destination image.
copyROI8u :: ImageGray -> ImageGray -> IO ()
copyROI8u (G r) (G im) = ippiCopy_8u_C1R // src im (vroi im) // dst r (vroi im) // checkIPP "copyROI8u" [im]

-- | Copies the roi of the input image into the roi of the destination image.
copyROI8u' :: ImageGray -> ROI -> ImageGray -> ROI -> IO ()
copyROI8u' (G im) r1 (G r) r2 = ippiCopy_8u_C1R // src im r1 // dst r r2 // checkIPP "copyROI8u'" [im]

-- | Copies the roi of the input image into the roi of the destination image.
copyROI8u3' :: ImageRGB -> ROI -> ImageRGB -> ROI -> IO ()
copyROI8u3' (C im) r1 (C r) r2 = ippiCopy_8u_C3R // src im r1 // dst r r2 // checkIPP "copyROI8u3'" [im]


-- | extracts a given channel of a 8uC3 image into a 8uC1 image
getChannel :: Int -> ImageRGB -> ImageGray
getChannel c (C im) = unsafePerformIO $ do
    G r <- image (isize im)
    let roi = vroi im
        im' = im {ptr = ptr im `plusPtr` c}
    ippiCopy_8u_C3C1R // src im' roi // dst r roi // checkIPP "ippiCopy_8u_C3C1R" [im]
    return $ modifyROI (const roi) (G r)

-- | Creates an 8uC3 image from three 8uC1 images. (to do consistency)
putChannels :: (ImageGray,ImageGray,ImageGray) -> ImageRGB
putChannels (G r, G g, G b) = unsafePerformIO $ do
    C c <- image (isize r)
    let roi = vroi r
        r' = c {ptr = ptr c `plusPtr` 0}
        g' = c {ptr = ptr c `plusPtr` 1}
        b' = c {ptr = ptr c `plusPtr` 2}
    ippiCopy_8u_C1C3R // src r roi // dst r' roi // checkIPP "ippiCopy_8u_C1C3R-1" [c]
    ippiCopy_8u_C1C3R // src g roi // dst g' roi // checkIPP "ippiCopy_8u_C1C3R-2" [c]
    ippiCopy_8u_C1C3R // src b roi // dst b' roi // checkIPP "ippiCopy_8u_C1C3R-3" [c]
    return $ modifyROI (const roi) (C c)


simplefun1F ippfun roifun msg = g where
    g (F im) = do
        r <- imgAsR1 roifun im
        cr1 ippfun im r // checkIPP msg [im]
        return (F r) 

simplefun1G ippfun roifun msg = g where
    g (G im) = do
        r <- imgAsR1 roifun im
        cr1 ippfun im r // checkIPP msg [im]
        return (G r)

simplefun1C ippfun roifun msg = g where
    g (C im) = do
        r <- imgAsR1 roifun im
        cr1 ippfun im r // checkIPP msg [im]
        return (C r)


-- | Creates a image of the same size as the source and copies its roi.
copy32f :: ImageFloat -> IO ImageFloat
copy32f = simplefun1F ippiCopy_32f_C1R id "copy32f"

-- | Creates a image of the same size as the source and copies its roi.
copy8u :: ImageGray -> IO ImageGray
copy8u = simplefun1G ippiCopy_8u_C1R id "copy8u"

-- | Creates a image of the same size as the source and copies its roi.
copy8uC3 :: ImageRGB -> IO ImageRGB
copy8uC3 = simplefun1C ippiCopy_8u_C3R id "copy8uC3"


-- | The result contains the absolute values of the pixels in the input image.
abs32f :: ImageFloat -> IO ImageFloat
abs32f  = simplefun1F ippiAbs_32f_C1R  id "abs32f"

-- | The result contains the square roots of the pixels in the input image.
sqrt32f :: ImageFloat -> IO ImageFloat
sqrt32f = simplefun1F ippiSqrt_32f_C1R id "sqrt32f"

-- | Applies a vertical Sobel filter (typically used for computing gradient images).
sobelVert :: ImageFloat -> IO ImageFloat
sobelVert = simplefun1F ippiFilterSobelVert_32f_C1R (shrink (1,1)) "sobelVert"

-- | Applies a horizontal Sobel filter (typically used for computing gradient images).
sobelHoriz ::ImageFloat -> IO ImageFloat
sobelHoriz = simplefun1F ippiFilterSobelHoriz_32f_C1R (shrink (1,1)) "sobelHoriz"

data Mask = Mask3x3 | Mask5x5
code Mask3x3 = 33
code Mask5x5 = 55

data AlgHint = AlgHintNone | AlgHintFast | AlgHintAccurate
codeAlgHint AlgHintNone     = 0
codeAlgHint AlgHintFast     = 1
codeAlgHint AlgHintAccurate = 2

-- | Convolution with a gaussian mask of the desired size.
gauss :: Mask -> ImageFloat -> IO ImageFloat
gauss mask = simplefun1F f (shrink (s,s)) "gauss" where
    s = case mask of
                Mask3x3 -> 1
                Mask5x5 -> 2
    f ps ss pd sd r = ippiFilterGauss_32f_C1R ps ss pd sd r (code mask)

-- | Convolution with a laplacian mask of the desired size.
laplace :: Mask -> ImageFloat -> IO ImageFloat
laplace mask = simplefun1F f (shrink (s,s)) "laplace" where
    s = case mask of
                Mask3x3 -> 1
                Mask5x5 -> 2
    f ps ss pd sd r = ippiFilterLaplace_32f_C1R ps ss pd sd r (code mask)

-- | Median Filter
median :: Mask -> ImageGray -> IO ImageGray
median mask = simplefun1G f (shrink (s,s)) "median" where
    s = case mask of
                Mask3x3 -> 1
                Mask5x5 -> 2
    mk = case mask of
                Mask3x3 -> ippRect 3 3
                Mask5x5 -> ippRect 5 5
    f ps ss pd sd r = ippiFilterMedian_8u_C1R ps ss pd sd r mk (ippRect s s)

-- | High pass filter
highPass8u :: Mask -> ImageGray -> IO ImageGray
highPass8u mask = simplefun1G f (shrink (s,s)) "highPass8u" where
    s = case mask of
                Mask3x3 -> 1
                Mask5x5 -> 2
    f ps ss pd sd r = ippiFilterHipass_8u_C1R ps ss pd sd r (code mask)


-- | The result is the source image in which the pixels verifing the comparation with a threshold are set to a desired value.
thresholdVal32f :: Float          -- ^ threshold
                -> Float          -- ^ value
                -> IppCmp         -- ^ comparison function
                -> ImageFloat     -- ^ source image
                -> IO ImageFloat  -- ^ result
thresholdVal32f t v cmp = simplefun1F f id "thresholdVal32f" where
    f ps ss pd sd r = ippiThreshold_Val_32f_C1R ps ss pd sd r t v (codeCmp cmp)

-- | The result is the source image in which the pixels verifing the comparation with a threshold are set to a desired value.
thresholdVal8u :: CUChar          -- ^ threshold
                -> CUChar          -- ^ value
                -> IppCmp         -- ^ comparison function
                -> ImageGray     -- ^ source image
                -> IO ImageGray  -- ^ result
thresholdVal8u t v cmp = simplefun1G f id "thresholdVal8u" where
    f ps ss pd sd r = ippiThreshold_Val_8u_C1R ps ss pd sd r t v (codeCmp cmp)

-- | Binarizes an image.
binarize8u :: CUChar -- ^ threshold
           -> Bool   -- ^ True = higher values -> 255, False = higher values -> 0
           -> ImageGray -- ^ image source
           -> IO ImageGray
binarize8u th True im =
    thresholdVal8u th 0 IppCmpLess im >>=
    thresholdVal8u (th-1) 255 IppCmpGreater

binarize8u th False im =
    binarize8u th True im >>= not8u


-- | Changes each pixel by the maximum value in its neighbourhood of given diameter.
filterMax32f :: Int -> ImageFloat -> IO ImageFloat
filterMax32f sz = simplefun1F f (shrink (d,d)) "filterMax32f" where
    d = (sz-1) `quot` 2
    f ps ss pd sd r = ippiFilterMax_32f_C1R ps ss pd sd r (ippRect sz sz) (ippRect d d)

-- | dilatation 3x3
dilate3x3 :: ImageGray -> IO ImageGray
dilate3x3 = simplefun1G ippiDilate3x3_8u_C1R (shrink (1,1)) "dilate3x3"

-- | erosion 3x3
erode3x3 :: ImageGray -> IO ImageGray
erode3x3 = simplefun1G ippiErode3x3_8u_C1R (shrink (1,1)) "dilate3x3"

-- | logical NOT
not8u :: ImageGray -> IO ImageGray
not8u = simplefun1G ippiNot_8u_C1R id "not"

-- | logical AND
and8u :: ImageGray -> ImageGray -> IO ImageGray
and8u = simplefun2G ippiAnd_8u_C1R intersection "and8u"

-- | logical OR
or8u :: ImageGray -> ImageGray -> IO ImageGray
or8u = simplefun2G ippiOr_8u_C1R intersection "or8u"

---------------------------------------------

simplefun2 ippfun roifun msg = g where
    g (F im1) (F im2) = do
        r <- imgAsR2 roifun im1 im2
        cr2 ippfun im1 im2 r // checkIPP msg [im1,im2]
        return (F r)

simplefun2G ippfun roifun msg = g where
    g (G im1) (G im2) = do
        r <- imgAsR2 roifun im1 im2
        cr2 ippfun im1 im2 r // checkIPP msg [im1,im2]
        return (G r)


infixl 7  `mul32f`
infixl 6  `add32f`, `sub32f`
-- | Pixel by pixel multiplication.
mul32f :: ImageFloat -> ImageFloat -> IO ImageFloat
mul32f = simplefun2 ippiMul_32f_C1R intersection "mul32f"

-- | Pixel by pixel addition.
add32f :: ImageFloat -> ImageFloat -> IO ImageFloat
add32f = simplefun2 ippiAdd_32f_C1R intersection "add32f"

-- | Pixel by pixel substraction.
sub32f :: ImageFloat -> ImageFloat -> IO ImageFloat
sub32f = flip $ simplefun2 ippiSub_32f_C1R intersection "sub32f" -- more natural argument order

-- | Pixel by pixel substraction.
sub8u :: Int -> ImageGray -> ImageGray -> IO ImageGray
sub8u k = flip $ simplefun2G f intersection "sub8u"
    where f ps1 ss1 ps2 ss2 pd sd r = ippiSub_8u_C1RSfs ps1 ss1 ps2 ss2 pd sd r k

-- | Absolute difference
absDiff8u :: ImageGray -> ImageGray -> IO ImageGray
absDiff8u = simplefun2G ippiAbsDiff_8u_C1R intersection "absDiff8u"

absDiff32f :: ImageFloat -> ImageFloat -> IO ImageFloat
absDiff32f = simplefun2 ippiAbsDiff_32f_C1R intersection "absDiff32f"

-- | Sum of all pixels in the roi a 8u image
sum8u :: ImageGray -> IO Double
sum8u (G im) = do
    pf <- malloc
    (ippiSum_8u_C1R // dst im (vroi im)) pf // checkIPP "sum8u" [im]
    r <- peek pf
    return r

sum32f :: ImageFloat -> IO Double
sum32f (F im) = do
    pf <- malloc
    (ippiSum_32f_C1R // dst im (vroi im)) pf // checkIPP "sum32f" [im]
    r <- peek pf
    return r


-- | Multiplies the pixel values of an image by a given value.
scale32f :: Float -> ImageFloat -> IO ImageFloat
scale32f v = simplefun1F f id "mulC32f" where
    f ps ss pd sd r = ippiMulC_32f_C1R ps ss v pd sd r

codeCmp IppCmpLess      = 0
codeCmp IppCmpLessEq    = 1
codeCmp IppCmpEq        = 2
codeCmp IppCmpGreaterEq = 3
codeCmp IppCmpGreater   = 4

-- | Comparison options
data IppCmp = IppCmpLess | IppCmpLessEq | IppCmpEq | IppCmpGreaterEq | IppCmpGreater

-- | The result is the pixelswise comparation of the two source images.
compare32f :: IppCmp -> ImageFloat -> ImageFloat -> IO ImageGray
compare32f cmp (F im1) (F im2) = do
    r <- img Gray (isize im1)
    let roi = intersection (vroi im1) (vroi im2)
    (ippiCompare_32f_C1R // src im1 roi // src im2 roi // dst r roi) (codeCmp cmp) // checkIPP "compare32f" [im1,im2]
    return (G r {vroi = roi})

-- | Creates a copy of the source image only on corresponding pixels in which mask=255
copyMask32f :: ImageFloat    -- ^ source image
            -> ImageGray     -- ^ mask image
            -> IO ImageFloat -- ^ result
copyMask32f (F im) (G mask) = do
    r <- imgAs im
    let roi = intersection (vroi im) (vroi mask)
    set32f 0.0 (fullroi r) (F r)
    ippiCopy_32f_C1MR // src im roi // dst r roi // src mask roi // checkIPP "copyMask32f" [im,mask]
    return $ F r {vroi = roi}

-- | Nonmaximum supression. Given an I32f image returns a copy of the input image with all the pixels which are not local maxima set to 0.0.
localMax :: Int         -- ^ diameter of the filterMax32f
         -> ImageFloat  -- ^ input image
         -> IO ImageFloat   -- ^ result
localMax d g = do
    mg   <- filterMax32f d g
    mask <- compare32f IppCmpEq mg g
    r    <- copyMask32f g mask
    return r

-- | Given a desired size (height, width) it produces a test image using @ippiImageJaehne_32f_C1R@.
jaehne32f :: Size -> IO ImageFloat
jaehne32f s = do
    w <- img I32f s
    ippiImageJaehne_32f_C1R // dst w (fullroi w) // checkIPP "ippiImageJaehne_32f_C1R" [w]
    return (F w)

-- | Given an image I32f, computes the first and second order derivatives (gx,gy,gxx,gyy,gxy).
secondOrder :: ImageFloat -> IO (ImageFloat,ImageFloat,ImageFloat,ImageFloat,ImageFloat)
secondOrder image = do
    gx  <- sobelVert image
    gy  <- sobelHoriz image
    gxx <- sobelVert gx
    gyy <- sobelHoriz gy
    gxy <- sobelHoriz gx
    return (gx,gy,gxx,gyy,gxy)    

-- | Obtains the determinant of the hessian operator from the 'secondOrder' derivatives.
hessian :: (ImageFloat,ImageFloat,ImageFloat,ImageFloat,ImageFloat) -> IO ImageFloat
hessian (gx,gy,gxx,gyy,gxy) = do
    ab <- gxx `mul32f` gyy
    cc <- gxy `mul32f` gxy
    h  <- ab  `sub32f` cc
    return h

-- | Repeats an action a given number of times. For example, @(3 `times` fun) x = fun x >>= fun >>= fun@
times :: (Monad m, Num a1) => a1 -> (a -> m a) -> a -> m a
times 0 f = return
times n f = g where
    g x = do
        v <- f x >>= times (n-1) f
        return v

-- | Returns the minimum and maximum value in an image32f
minmax :: ImageFloat -> IO (Float,Float)
minmax (F im) = do
    mn <- malloc 
    mx <- malloc
    (ippiMinMax_32f_C1R // dst im (vroi im)) mn mx // checkIPP "minmax" [im]
    a <- peek mn
    b <- peek mx
    free mn
    free mx
    return (a,b)


-- | Returns the maximum value and its position in the roi of an image32f. The position is relative to the ROI.
maxIndx :: ImageFloat -> IO (Float,Pixel)
maxIndx (F im) = do
    mx <- malloc
    px <- malloc
    py <- malloc
    (ippiMaxIndx_32f_C1R // dst im (vroi im)) mx px py // checkIPP "maxIndx" [im]
    v <- peek mx
    x <- peek px
    y <- peek py
    free mx
    free px
    free py
    return (v,Pixel y x)

-- | Returns the maximum value and its position in the roi of an image8u. The position is relative to the image.
maxIndx8u :: ImageGray -> (CUChar,Pixel)
maxIndx8u (G im) = unsafePerformIO $ do
    let roi@(ROI r1 r2 c1 c2) = vroi im
    mx <- malloc
    px <- malloc
    py <- malloc
    (ippiMaxIndx_8u_C1R // dst im roi) mx px py // checkIPP "maxIndx8u" [im]
    v <- peek mx
    x <- peek px
    y <- peek py
    free mx
    free px
    free py
    return (v,Pixel (r1+y) (c1+x))


-- | Explores an image and returns a list of pixels (as [row,column]) where the image is greater than 0.0.
getPoints32f :: Int -> ImageFloat -> IO [Pixel]
getPoints32f mx (F im) = do
    r <- mallocArray (2*mx)
    ptot <- malloc
    ok <- c_getPoints32f (castPtr (ptr im)) (step im) 
                   (r1 (vroi im)) (r2 (vroi im)) (c1 (vroi im)) (c2 (vroi im))
                   mx ptot r
    touchForeignPtr (fptr im)
    tot <- peek ptot
    hp <- peekArray tot r
    free ptot
    free r
    return (partitPixel hp)

-- | Partitions a list into a list of lists of a given length.
partit :: Int -> [a] -> [[a]]
partit _ [] = []
partit n l  = take n l : partit n (drop n l)

partitPixel :: [Int] -> [Pixel]
partitPixel [] = []
partitPixel [a] = error "partitPixel on a list with odd number of entries"
partitPixel (r:c:l) = Pixel r c : partitPixel l

----------------------------------------------------------
-- TO DO: parameters with a record

-- | Returns a list of interest points in the image (as unnormalized [x,y]). They are the local minimum of the determinant of the hessian (saddlepoints).
getCorners :: Int       -- ^ degree of smoothing (e.g. 1)
           -> Int       -- ^ radius of the localmin filter (e.g. 7)
           -> Float     -- ^ fraction of the maximum response allowed (e.g. 0.1)
           -> Int       -- ^ maximum number of interest points
           -> ImageFloat  -- ^ source image
           -> IO [Pixel]  -- ^ result
getCorners smooth rad prop maxn im = do
    let suaviza = smooth `times` gauss Mask5x5
    h <- suaviza im >>= secondOrder >>= hessian >>= scale32f (-1.0)
    (mn,mx) <- minmax h
    hotPoints <- localMax rad h
              >>= thresholdVal32f (mx*prop) 0.0 IppCmpLess
              >>= getPoints32f maxn
    return hotPoints

--------------------------------------------------------------------
inter_NN         =  1 :: Int
inter_LINEAR     =  2 :: Int
inter_CUBIC      =  4 :: Int
inter_SUPER      =  8 :: Int
inter_LANCZOS    = 16 :: Int
--inter_SMOOTH_EDGE = (1 << 31) :: Int

genResize f s dst droi im sroi interp = do
               f (ptr im) (step im) (height $ isize im) (width $ isize im)
                 (r1 sroi) (r2 sroi) (c1 sroi) (c2 sroi)
                 (ptr dst) (step dst)
                 (r1 droi) (r2 droi) (c1 droi) (c2 droi)
                 interp // checkIPP s [im]

-- | Resizes the roi of a given image.
resize32f :: Size -> ImageFloat -> IO ImageFloat
resize32f s (F im) = do
    r <- img I32f s
    genResize c_resize32f "genResize32f" r (fullroi r) im (vroi im) inter_LINEAR
    return (F r)

-- | Resizes the roi of a given image.
resize8u :: Size -> ImageGray -> IO ImageGray
resize8u s (G im) = do
    r <- img Gray s
    genResize c_resize8u "genResize8u" r (fullroi r) im (vroi im) inter_LINEAR
    return (G r)

-- | Resizes the roi of a given image.
resize8u3 :: Size -> ImageRGB -> IO ImageRGB
resize8u3 s (C im) = do
    r <- img RGB s
    genResize c_resize8u3 "genResize8u3" r (fullroi r) im (vroi im) inter_LINEAR
    return (C r)


----------------------------------------------------------------------

-- | Canny's edge detector.
canny :: (ImageFloat,ImageFloat) -- ^ image gradient (dx,dy)
      -> (Float,Float)           -- ^ low and high threshold
      -> IO ImageGray               -- ^ resulting image
canny (F dx, F dy) (l,h) = do
    r <- img Gray (isize dx)
    ps <- malloc
    let roi = intersection (vroi dx) (vroi dy)
    ippiCannyGetSize (roiSize roi) ps // checkIPP "ippiCannyGetSize" []
    s <- peek ps
    buffer <- mallocBytes s
    (ippiCanny_32f8u_C1R // src dx roi // src dy roi // dst r roi) l h buffer
                         // checkIPP "ippiCanny_32f8u_C1R" [dx,dy]
    free buffer
    free ps
    return (G r {vroi = roi})

-----------------------------------------------------------------------

-- | Histogram of a 8u image. For instance, @histogram [0,64 .. 256] g@ computes an histogram with four bins equally spaced in the image range.
histogram :: [Int] -- ^ bin bounds
          -> ImageGray -- ^ source image
          -> [Int]     -- result
histogram bins (G im) = unsafePerformIO $ do
    let n = length bins
    pbins <- newArray bins
    pr <- mallocArray n
    (ippiHistogramRange_8u_C1R // dst im (vroi im)) pr pbins n // checkIPP "histogram" [im]
    r <- peekArray (n-1) pr
    free pbins
    free pr
    return r

-- normalized histogram
histogramN bins im = map ((*sc).fromIntegral) h where
    h = histogram bins im
    ROI r1 r2 c1 c2 = theROI im
    sc = (1.0::Double) / fromIntegral ((r2-r1+1)*(c2-c1+1))

-----------------------------------------------------------------------

-- | Discrete cosine transform of a 32f image.
dct :: ImageFloat -> IO ImageFloat
dct = genDCT auxDCTFwd_32f_C1R "dct"

-- | Inverse discrete cosine transform of a 32f image.
idct :: ImageFloat -> IO ImageFloat
idct = genDCT auxDCTInv_32f_C1R "idct"

genDCT auxfun name (F im) = do
    r <- imgAsR1 id im
    --set32f 0.5 (fullroi r) (F r)
    auxfun (castPtr (ptr im)) (step im)
           (r1 (vroi im)) (r2 (vroi im)) (c1 (vroi im)) (c2 (vroi im))
           (castPtr (ptr r)) (step r)
           (r1 (vroi r)) (r2 (vroi r)) (c1 (vroi r)) (c2 (vroi r))
           // checkIPP name [im]
    return (F r)

------------------------------------------------------------------------

-- | Creates a function to compute the FFT of a 32f image. The resulting function produces 32f images in complex packed format. The dimensions of the ROI must be powers of two.
genFFT :: Int -- ^ ordx
       -> Int -- ^ ordy
       -> FFTNormalization
       -> AlgHint
       -> IO (ImageFloat -> IO (ImageFloat)) -- ^ resulting FFT function
genFFT ordx ordy flag alg = do
    ptrSt <- malloc
    ippiFFTInitAlloc_R_32f ptrSt ordx ordy (codeFFTFlag flag) (codeAlgHint alg) // checkIPP "FFTInitAlloc" []
    st <- peek ptrSt
    pn <- malloc
    ippiFFTGetBufSize_R_32f st pn // checkIPP "FFTGetBufSize" []
    n <- peek pn
    buf <- mallocBytes n
    let fft (F im) = do
        r <- imgAsR1 id im
        (ippiFFTFwd_RToPack_32f_C1R // src im (vroi im) // src r (vroi r)) st buf // checkIPP "FFTFwd_RToPack_32f_C1R" [im]
        return (F r)
    return fft

-- | Normalization options for the FFT
data FFTNormalization = DivFwdByN | DivInvByN | DivBySqrtN | NoDivByAny
codeFFTFlag DivFwdByN  = 1
codeFFTFlag DivInvByN  = 2
codeFFTFlag DivBySqrtN = 4
codeFFTFlag NoDivByAny = 8

-- | Computes the magnitude of a complex packed 32f image (typically produced by the FFT computed by the result of 'genFFT')
magnitudePack :: ImageFloat -> IO (ImageFloat)
magnitudePack = simplefun1F ippiMagnitudePack_32f_C1R id "magnitudePack"

-- | Relocates the low frequencies of 'magnitudePack' in the center of the ROI.
powerSpectrum :: ImageFloat -> IO (ImageFloat)
powerSpectrum (F im) = do
    r <- imgAs im
    let ROI r1 r2 c1 c2 = vroi im
    set32f 0 (vroi im) (F r)
    let cm = ((c2-c1+1) `div` 2)
    let rm = ((r2-r1+1) `div` 2)
    let sroi = ROI r1 (r1+rm-1) c1 (c1+cm-1)
    let droi = shift (rm,cm) sroi
    ippiCopy_32f_C1R // src im sroi // dst r droi // checkIPP "powerSpectrum-1" [im]
    let droi = ROI r1 (r1+rm-1) c1 (c1+cm-1)
    let sroi = shift (rm,cm) droi
    ippiCopy_32f_C1R // src im sroi // dst r droi // checkIPP "powerSpectrum-2" [im]
    let sroi = ROI r1 (r1+rm-1) (c1+cm) c2
    let droi = shift (rm,-cm) sroi
    ippiCopy_32f_C1R // src im sroi // dst r droi // checkIPP "powerSpectrum-3" [im]
    let droi = ROI r1 (r1+rm-1) (c1+cm) c2
    let sroi = shift (rm,-cm) droi
    ippiCopy_32f_C1R // src im sroi // dst r droi // checkIPP "powerSpectrum-4" [im]
    return (F r {vroi = vroi im})

-- | Distance transform: Given an 8u image with feature pixels = 0, computes a 32f image with the distance from each pixel to the nearest feature pixel. The argument metrics is a list of float with two (for a 3x3 mask) or three elements (for a 5x5 mask), which specify respectively the distances between pixels which share an edge, a corner and pixels at distance of chess knight move. For example, for L2 metrics we use [1,1.4] (3x3 mask) or [1,1.4,2.2] (5x5 mask). If metrics is not valid (e.g. []), then [1,1.4] is used.
distanceTransform :: [Float]       -- ^ metrics
                  -> ImageGray     -- ^ source image 
                  -> IO ImageFloat -- ^ result

distanceTransform (m@[_,_]) = genDistanceTransform ippiDistanceTransform_3x3_8u32f_C1R m
distanceTransform (m@[_,_,_]) = genDistanceTransform ippiDistanceTransform_5x5_8u32f_C1R m
distanceTransform _ = distanceTransform [1,1.4]

genDistanceTransform f metrics (G im) = do
    pmetrics <- newArray metrics
    r' <- img I32f (isize im)
    let r = r' {vroi = vroi im}
    (f // src im (vroi im) // dst r (vroi r)) pmetrics // checkIPP "ippiDistanceTransform_?_8u32f_C1R" [im]
    free pmetrics
    return (F r)


-- | Fills (as a side effect) a connected component in the image, starting at the seed pixel. It returns
-- the enclosing ROI, area and value. This is the 8con version.
floodFill8u :: ImageGray -> Pixel -> CUChar -> IO (ROI, Int, CUChar)
floodFill8u (G im) (Pixel r c) val = do
    let roi@(ROI r1 r2 c1 c2) = vroi im
    pregion <- mallocBytes 48 -- (8+3*8+(4+4+4+4))
    pbufsize <- malloc
    ippiFloodFillGetSize (roiSize roi) pbufsize // checkIPP "ippiFloodFillGetSize" []
    bufsize <- peek pbufsize
    buf <- mallocBytes bufsize
    free pbufsize
    (ippiFloodFill_8Con_8u_C1IR // dst im (vroi im)) (ippRect (c-c1) (r-r1)) val pregion buf // checkIPP "ippiFloodFill_8Con_8u_C1IR" [im]
    free buf
    [area,value1,value2,value3] <- peekArray 4 (castPtr pregion :: Ptr Double)
    [_,_,_,_,_,_,_,_,x,y,w,h] <- peekArray 12 (castPtr pregion :: Ptr Int)
    free pregion
    return (ROI (r1+y) (r1+y+h-1) (c1+x) (c1+x+w-1), round area, round value1)

-- | Fills (as a side effect) a connected component in the image, starting at the seed pixel.
-- This version admits a lower and higher difference in the pixel values.
-- It returns the enclosing ROI, area and value. This is the 8con version.
floodFill8uGrad :: ImageGray -> Pixel -> CUChar -> CUChar -> CUChar-> IO (ROI, Int, CUChar)
floodFill8uGrad (G im) (Pixel r c) dmin dmax val = do
    let roi@(ROI r1 r2 c1 c2) = vroi im
    pregion <- mallocBytes 48 -- (8+3*8+(4+4+4+4))
    pbufsize <- malloc
    ippiFloodFillGetSize (roiSize roi) pbufsize // checkIPP "ippiFloodFillGetSize" []
    bufsize <- peek pbufsize
    --print bufsize
    buf <- mallocBytes bufsize
    free pbufsize
    (ippiFloodFill_Grad8Con_8u_C1IR // dst im (vroi im)) (ippRect (c-c1) (r-r1)) val dmin dmax pregion buf // checkIPP "ippiFloodFill_Grad8Con_8u_C1IR" [im]
    free buf
    [area,value1,value2,value3] <- peekArray 4 (castPtr pregion :: Ptr Double)
    [_,_,_,_,_,_,_,_,x,y,w,h] <- peekArray 12 (castPtr pregion :: Ptr Int)
    free pregion
    return (ROI (r1+y) (r1+y+h-1) (c1+x) (c1+x+w-1), round area, round value1)

-- | Histogram of the 256 possible configurations of 3x3 image patches thresholded by the central pixel. Works inside the image ROI.
lbp :: Int       -- ^ threshold tolerance
    -> ImageGray -- ^ source image
    -> [Int]     -- result
lbp th (G im) = unsafePerformIO $ do
    hist <- mallocArray 256
    lbp8u th (ptr im) (step im) (r1 (vroi im)) (r2 (vroi im)) (c1 (vroi im)) (c2 (vroi im)) hist
        // checkIPP "lbp" [im]
    r <- peekArray 256 hist
    free hist
    return r

-- normalized lbp histogram
lbpN t im = map ((*sc).fromIntegral) (tail h) where
    h = lbp t im
    ROI r1 r2 c1 c2 = theROI im
    sc = (256.0::Double) / fromIntegral ((r2-r1-1)*(c2-c1-1))

----------------------------------------------------------------------------------------

-- | to do
hsvCodeTest :: Int -> Int -> Int -> ImageRGB -> IO ()
hsvCodeTest b g w (C im) = do
    hsvcodeTest b g w (ptr im) (step im) (r1 (vroi im)) (r2 (vroi im)) (c1 (vroi im)) (c2 (vroi im))
        // checkIPP "hsvcodeTest" [im]

-- | to do
hsvCode :: Int -> Int -> Int -> ImageRGB -> ImageGray
hsvCode b g w (C im) = unsafePerformIO $ do
    G r <- image (isize im)
    set8u 0 (theROI (G r)) (G r)
    hsvcode b g w
            (ptr im) (step im)
            (ptr r) (step r)
            (r1 (vroi im)) (r2 (vroi im)) (c1 (vroi im)) (c2 (vroi im))
            // checkIPP "hsvcode" [im]
    return $ modifyROI (const (vroi im)) (G r)

----------------------------------------------------------------------------------------

warpOn' h r im f met s = do
    coefs <- newArray (concat h)
    let Size h w = isize im
    f (ptr im) (step im) h w
                           (r1 (vroi im)) (r2 (vroi im)) (c1 (vroi im)) (c2 (vroi im))
                           (ptr r) (step r)
                           (r1 (vroi r)) (r2 (vroi r)) (c1 (vroi r)) (c2 (vroi r))
                           coefs met //warningIPP s [im]
    free coefs

warpOn8u  h (G r) (G im) = warpOn' h r im warpPerspectiveGray inter_LINEAR "warpOn8u"
warpOn32f h (F r) (F im) = warpOn' h r im warpPerspective32f inter_LINEAR "warpOn32f"
warpOn8u3 h (C r) (C im) = warpOn' h r im warpPerspectiveRGB inter_LINEAR "warpOn8u3"

----------------------------------------------------------------------------------------

-- | Mirror (as a side effect) an image.
mirror8u :: ImageGray -> Int -> IO ()
mirror8u (G im) axis = (ippiMirror_8u_C1IR // dst im (vroi im)) axis // checkIPP "ippiMirror_8u_C1IR" [im]
