module Scenario.Registry
  ( allScenarios
  , findByName
  , findByTag
  ) where

import Scenario.Types
import Data.Text  (Text)
import Data.Maybe (listToMaybe)
import qualified Scenario.Builtin.LrscInterrupt as S001

allScenarios :: [ScenarioSpec]
allScenarios =
  [ S001.spec
  ]

findByName :: Text -> Maybe ScenarioSpec
findByName name = listToMaybe (filter (\s -> sName s == name) allScenarios)

findByTag :: Tag -> [ScenarioSpec]
findByTag tag = filter (elem tag . sTags) allScenarios
