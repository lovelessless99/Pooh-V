module Coverage.Detector
  ( PatternDetector(..)
  , allDetectors
  ) where

import Coverage.Types              (SequencePattern(..))
import Core.Instruction            (Instruction)
import qualified Coverage.Builtin.Detectors as B

data PatternDetector = PatternDetector
  { pdPattern :: SequencePattern
  , pdDetect  :: [Instruction] -> Bool
  }

allDetectors :: [PatternDetector]
allDetectors =
  [ PatternDetector LrscPair           B.detectLrscPair
  , PatternDetector LrscSuccess        B.detectLrscSuccess
  , PatternDetector LrscFail           B.detectLrscFail
  , PatternDetector LoadUseDependency  B.detectLoadUse
  , PatternDetector BranchTaken        B.detectBranchTaken
  , PatternDetector BranchNotTaken     B.detectBranchNotTaken
  , PatternDetector BackwardBranch     B.detectBackwardBranch
  , PatternDetector ForwardBranch      B.detectForwardBranch
  , PatternDetector CallReturnPair     B.detectCallReturn
  , PatternDetector TailCall           B.detectTailCall
  , PatternDetector FenceBeforeAtomic  B.detectFenceBeforeAtomic
  , PatternDetector ExceptionReturn    B.detectExceptionReturn
  , PatternDetector WfiWithInterrupt   B.detectWfi
  , PatternDetector InstructionFusion  B.detectFusion
  , PatternDetector CsrReadModifyWrite B.detectCsrRmw
  ]
