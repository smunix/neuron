{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE Rank2Types #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Neuron.Web.Query.View
  ( renderQueryResult,
    renderZettelLink,
    renderZettelLinkIDOnly,
    zettelUrl,
    tagUrl,
    style,
  )
where

import qualified Clay as C
import Clay ((?), Css, em)
import Control.Monad.Except
import Data.Default
import Data.Dependent.Sum
import qualified Data.Map.Strict as Map
import Data.Some
import Data.TagTree (Tag (..), TagNode (..), TagPattern (..), constructTag, foldTagTree, tagMatchAny, tagTree)
import qualified Data.Text as T
import Data.Tree
import Neuron.Web.Route
import qualified Neuron.Web.Theme as Theme
import Neuron.Web.Widget
import Neuron.Zettelkasten.Connection
import Neuron.Zettelkasten.ID
import Neuron.Zettelkasten.Query.Theme (LinkView (..), ZettelsView (..))
import Neuron.Zettelkasten.Zettel
import Reflex.Dom.Core hiding (count, tag)
import Relude

-- | Render the query results.
renderQueryResult ::
  DomBuilder t m => DSum ZettelQuery Identity -> NeuronWebT t m ()
renderQueryResult = \case
  ZettelQuery_ZettelByID _zid (fromMaybe def -> conn) :=> Identity target -> do
    renderZettelLink (Just conn) Nothing target
  q@(ZettelQuery_ZettelsByTag pats (fromMaybe def -> conn) view) :=> Identity res -> do
    el "section" $ do
      renderQuery $ Some q
      elClass "table" "ui very basic table" $ el "tbody" $ do
        case zettelsViewGroupByTag view of
          False ->
            forM_ (subListOf (zettelsViewColumns view) res) $ \zs -> do
              el "tr" $ do
                forM_ zs $ \z -> do
                  el "td" $ do
                    renderZettelLink (Just conn) (Just $ zettelsViewLinkView view) z
          True ->
            forM_ (subListOf (zettelsViewColumns view) . Map.toList $ groupZettelsByTagsMatching pats res) $ \tagZettelGrpList -> do
              el "tr" $ do
                forM_ tagZettelGrpList $ \(tag, zettelGrp) -> do
                  el "td" $ do
                    -- el "section" $ do
                      elClass "table" "ui very basic selectable table" $ el "tbody" $ do
                        el "tr" $ do
                          el "th" $ do
                            elClass "span" "ui basic pointing below grey label" $ do
                              semanticIcon "tag"
                              text $ unTag tag
                        forM_ zettelGrp $ \z ->
                          el "tr" $ do
                            el "td" $ do
                              renderZettelLink (Just conn) (Just $ zettelsViewLinkView view) z
  q@(ZettelQuery_Tags _) :=> Identity res -> do
    el "section" $ do
      renderQuery $ Some q
      renderTagTree $ foldTagTree $ tagTree res
  where
    -- TODO: Instead of doing this here, group the results in runQuery itself.
    groupZettelsByTagsMatching pats matches =
      fmap sortZettelsReverseChronological $ Map.fromListWith (<>) $ flip concatMap matches $ \z ->
        flip concatMap (zettelTags z) $ \t -> [(t, [z]) | tagMatchAny pats t]
    subListOf :: Int -> [a] -> [[a]]
    subListOf _ [] = []
    subListOf n as
      | length as <= n = [as]
      | otherwise = go n as []
      where
        go _ [] cur = cur:(subListOf n [])
        go 0 xs cur = cur:(subListOf n xs)
        go len (x:xs) cur = go (len-1) xs (x:cur)

renderQuery :: DomBuilder t m => Some ZettelQuery -> m ()
renderQuery someQ =
  elAttr "div" ("class" =: "ui horizontal divider" <> "title" =: "Neuron ZettelQuery") $ do
    case someQ of
      Some (ZettelQuery_ZettelByID _ _) ->
        blank
      Some (ZettelQuery_ZettelsByTag [] _mconn _mview) ->
        text "All zettels"
      Some (ZettelQuery_ZettelsByTag (fmap unTagPattern -> pats) _mconn _mview) -> do
        let qs = toText $ intercalate ", " pats
            desc = toText $ "Zettels tagged '" <> qs <> "'"
        elAttr "span" ("class" =: "ui basic pointing below black label" <> "title" =: desc) $ do
          semanticIcon "tags"
          text qs
      Some (ZettelQuery_Tags []) ->
        text "All tags"
      Some (ZettelQuery_Tags (fmap unTagPattern -> pats)) -> do
        let qs = toText $ intercalate ", " pats
        text $ "Tags matching '" <> qs <> "'"

-- | Render a link to an individual zettel.
renderZettelLink :: DomBuilder t m => Maybe Connection -> Maybe LinkView -> Zettel -> NeuronWebT t m ()
renderZettelLink conn (fromMaybe def -> LinkView {..}) Zettel {..} = do
  let connClass = show <$> conn
      rawClass = either (const $ Just "raw") (const Nothing) zettelError
      mextra =
        if linkViewShowDate
          then case zettelDay of
            Just day ->
              Just $ elTime day
            Nothing ->
              Nothing
          else Nothing
      classes :: [Text] = catMaybes $ [Just "zettel-link-container"] <> [connClass, rawClass]
  elClass "span" (T.intercalate " " classes) $ do
    forM_ mextra $ \extra ->
      elClass "span" "extra monoFont" $ extra
    let linkTooltip =
          if null zettelTags
            then Nothing
            else Just $ "Tags: " <> T.intercalate "; " (unTag <$> zettelTags)
    elAttr "span" ("class" =: "zettel-link" <> withTooltip linkTooltip) $ do
      neuronRouteLink (Some $ Route_Zettel zettelID) mempty $ text zettelTitle
  where
    withTooltip :: Maybe Text -> Map Text Text
    withTooltip = \case
      Nothing -> mempty
      Just s ->
        ( "data-tooltip" =: s
            <> "data-inverted" =: ""
            <> "data-position" =: "right center"
        )

-- | Like `renderZettelLink` but when we only have ID in hand.
renderZettelLinkIDOnly :: DomBuilder t m => ZettelID -> NeuronWebT t m ()
renderZettelLinkIDOnly zid =
  elClass "span" "zettel-link-container" $ do
    elClass "span" "zettel-link" $ do
      neuronRouteLink (Some $ Route_Zettel zid) mempty $ text $ zettelIDText zid

renderTagTree :: forall t m. DomBuilder t m => Forest (NonEmpty TagNode, Natural) -> m ()
renderTagTree t =
  divClass "tag-tree" $
    renderForest mempty t
  where
    renderForest :: [TagNode] -> Forest (NonEmpty TagNode, Natural) -> m ()
    renderForest ancestors forest =
      el "ul" $ do
        forM_ forest $ \tree ->
          el "li" $ renderTree ancestors tree
    renderTree :: [TagNode] -> Tree (NonEmpty TagNode, Natural) -> m ()
    renderTree ancestors (Node (tagNode, count) children) = do
      renderTag ancestors (tagNode, count)
      renderForest (ancestors <> toList tagNode) $ toList children
    renderTag :: [TagNode] -> (NonEmpty TagNode, Natural) -> m ()
    renderTag ancestors (tagNode, count) = do
      let tag = constructTag $ maybe tagNode (<> tagNode) $ nonEmpty ancestors
          tit = show count <> " zettels tagged"
          cls = bool "" "inactive" $ count == 0
      divClass "node" $ do
        elAttr "a" ("class" =: cls <> "title" =: tit <> "href" =: tagUrl tag) $ do
          text $ renderTagNode tagNode
    renderTagNode :: NonEmpty TagNode -> Text
    renderTagNode = \case
      n :| (nonEmpty -> mrest) ->
        case mrest of
          Nothing ->
            unTagNode n
          Just rest ->
            unTagNode n <> "/" <> renderTagNode rest

-- TODO: not using Rib for ghcjs, but factorize this
zettelUrl :: ZettelID -> Text
zettelUrl zid =
  zettelIDText zid <> ".html"

tagUrl :: Tag -> Text
tagUrl (Tag s) =
  "search.html?tag=" <> s

style :: Theme.Theme -> Css
style theme = do
  zettelLinkCss theme
  "div.tag-tree" ? do
    "div.node" ? do
      C.fontWeight C.bold
      "a.inactive" ? do
        C.color "#555"

zettelLinkCss :: Theme.Theme -> Css
zettelLinkCss neuronTheme = do
  let linkColor = Theme.withRgb neuronTheme C.rgb
  "span.zettel-link-container span.zettel-link a" ? do
    C.fontWeight C.bold
    C.color linkColor
    C.textDecoration C.none
  "span.zettel-link-container span.zettel-link a:hover" ? do
    C.backgroundColor linkColor
    C.color C.white
  "span.zettel-link-container span.extra" ? do
    C.color C.auto
    C.paddingRight $ em 0.3
  "span.zettel-link-container.folgezettel::after" ? do
    C.paddingLeft $ em 0.3
    C.content $ C.stringContent "ᛦ"
  "span.zettel-link-container.raw" ? do
    C.border C.solid (C.px 1) C.red
  "[data-tooltip]:after" ? do
    C.fontSize $ em 0.7
  "div.box" ? do
    C.display C.none
    C.width (C.pct 50)
  "a:hover + .box,.box:hover" ? do
    C.display C.block
    C.position C.relative
    C.zIndex 100
