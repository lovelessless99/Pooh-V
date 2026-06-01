module Test.Core.PMA (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Core.PMA
import Data.Word (Word64)

tests :: TestTree
tests = testGroup "PMA model"
  [ testCase "defaultMemoryLayout has a main memory region" $ do
      let regions' = regions defaultMemoryLayout
      any (\e -> pmaType e == MainMemory) regions' @?= True

  , testCase "lookup 0x80000000 returns MainMemory" $ do
      let result = lookupPMA 0x80000000 defaultMemoryLayout
      fmap pmaType result @?= Just MainMemory

  , testCase "lookup 0x10000000 returns IOMemory" $ do
      let result = lookupPMA 0x10000000 defaultMemoryLayout
      fmap pmaType result @?= Just IOMemory

  , testCase "lookup 0x00000000 returns Nothing (vacant)" $ do
      lookupPMA 0x00000000 defaultMemoryLayout @?= Nothing

  , testCase "main memory is cacheable" $ do
      let result = lookupPMA 0x80000000 defaultMemoryLayout
      fmap pmaCacheable result @?= Just Cacheable

  , testCase "IO memory is uncacheable" $ do
      let result = lookupPMA 0x10000000 defaultMemoryLayout
      fmap pmaCacheable result @?= Just Uncacheable
  ]
