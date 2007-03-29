-----------------------------------------------------------------------------
{- |
Module      :  Vision.Estimation
Copyright   :  (c) Alberto Ruiz 2006
License     :  GPL-style

Maintainer  :  Alberto Ruiz (aruiz at um dot es)
Stability   :  very provisional
Portability :  hmm...

Estimation of homogeneous transformations.

-}
-----------------------------------------------------------------------------

module Vision.Estimation
( homogSystem
, withNormalization
, estimateHomographyRansac
, estimateHomography
, estimateHomographyRaw
, ransac
, ransacProb
) where

import GSL hiding (Matrix, Vector)
import qualified GSL as G
import Classifier.Stat
import Vision.Geometry
import Data.List(transpose,nub,maximumBy,genericLength,elemIndex, genericTake)
import System.Random 
import Debug.Trace(trace)

type Matrix = G.Matrix Double
type Vector = G.Vector Double

matrix = fromLists :: [[Double]] -> Matrix
vector = fromList ::  [Double] -> Vector

svd = svdR'


-- overconstrained nullspace (mse solution of homogeneous linear system)
-- we assume that it is 1d 
homogSystem :: [[Double]] -> Vector
homogSystem coeffs = sol where
    r = length coeffs
    c = length (head coeffs)
    mat | r >= c   = matrix coeffs
        | r == c-1 = matrix (head coeffs : coeffs)
        | otherwise = error "homogSystem with rows<cols-1"
    (_,_,v) = svd mat
    sol = flatten $ dropColumns (c-1) v

estimateHomographyRaw dest orig = h where
    eqs = concat (zipWith eq dest orig)
    h = reshape 3 $ homogSystem eqs
    eq [bx,by] [ax,ay] = 
        [[  0,  0,  0,t14,t15,t16,t17,t18,t19],
         [t21,t22,t23,  0,  0,  0,t27,t28,t29],
         [t31,t32,t33,t34,t35,t36,  0,  0,  0]] where
            t14=(-ax)
            t15=(-ay)
            t16=(-1)
            t17=by*ax 
            t18=by*ay 
            t19=by
            t21=ax 
            t22=ay 
            t23=1
            t27=(-bx*ax) 
            t28=(-bx*ay) 
            t29=(-bx)
            t31=(-by*ax) 
            t32=(-by*ay) 
            t33=(-by)
            t34=bx*ax 
            t35=bx*ay
            t36=bx     

withNormalization lt estimateRelation dest orig = lt wd <> h <> wo where
    std = stat (matrix dest)
    sto = stat (matrix orig)
    nd = toLists (normalizedData std)
    no = toLists (normalizedData sto)
    h = estimateRelation nd no
    wd = whiteningTransformation std
    wo = whiteningTransformation sto 

estimateHomography = withNormalization inv estimateHomographyRaw   

------------------------------ RANSAC -------------------------------

partit :: Int -> [a] -> [[a]]
partit _ [] = []
partit n l  = take n l : partit n (drop n l)
-- take (length l `quot`n) $ unfoldr (\a -> Just (splitAt n a)) l   

compareBy f = (\a b-> compare (f a) (f b))

ransac' :: ([a]->t) -> (t -> a -> Bool) -> Int -> Int -> [a] -> (t,[a])
ransac' estimator isInlier n t dat = (result, goodData) where
    result = estimator goodData
    goodData = inliers bestModel
    bestModel = maximumBy (compareBy (length.inliers)) models
    models = take t (map estimator (samples n dat))
    inliers model = filter (isInlier model) dat

-- | @samples n list@ creates an infinite list of psuedorandom (using mkStdGen 0) subsets of n different elements taken from list
samples :: Int -> [a] -> [[a]]
samples n dat = map (map (dat!!)) goodsubsets where
    goodsubsets = filter ((==n).length) $ map nub $ partit n randomIndices
    randomIndices = randomRs (0, length dat -1) (mkStdGen 0)

ransacSize s p eps = 1 + (floor $ log (1-p) / log (1-(1-eps)^s))    ::Integer

position fun l = k where Just k = elemIndex (fun l) l


-- | adaptive ransac
ransac :: ([a]->t) -> (t -> a -> Bool) -> Int -> [a] -> (t,[a])
ransac estimator isInlier n dat = {-trace (show aux)-} (bestModel,inliers) where 
    models = map estimator (samples n dat)
    inls = map inliers models where inliers model = filter (isInlier model) dat 
    eps = map prop inls where prop l = 1 - genericLength l / genericLength dat
    ns = scanl1 min $ map (ransacSize n 0.99) eps 
    k = fst $ head $ dropWhile (\(k,n) -> k<n) (zip [1 ..] ns)
    p = position maximum (map length (genericTake k inls))
    bestModel = models!!p
    inliers = inls!!p
    aux = map length $ genericTake k inls

-- | adaptive ransac
--ransacProb :: ([a]->t) -> (t -> a -> Bool) -> Int -> [a] -> (t,[a])
ransacProb prob estimator isInlier n dat = {-trace (show aux)-} (bestModel,inliers) where 
    models = map estimator (samples n dat)
    inls = map inliers models where inliers model = filter (isInlier model) dat 
    eps = map prop inls where prop l = 1 - genericLength l / genericLength dat
    ns = scanl1 min $ map (ransacSize n prob) eps 
    k = debug $ fst $ head $ dropWhile (\(k,n) -> k<n) (zip [1 ..] ns)
    p = position maximum (map length (genericTake k inls))
    bestModel = models!!p
    inliers = inls!!p
    aux = map length $ genericTake k inls

debug x = trace (show x) x

--------------------------    

isInlierTrans t h (dst,src) = norm (vd - vde) < t 
    where vd  = vector dst
          vde = inHomog $ h <> homog (vector src)

estimateHomographyRansac dist dst orig = (h,inliers) where 
    h = estimateHomography a b where (a,b) = unzip inliers
    (_,inliers) = ransac estimator (isInlierTrans dist) 4 (zip dst orig)
    estimator l = estimateHomographyRaw a b where (a,b) = unzip l